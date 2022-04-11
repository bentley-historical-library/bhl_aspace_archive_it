require 'java'
require 'json'
require 'uri'
require 'net/http'
require 'jsonmodel_client'

class ArchiveItCollectionImporter < JobRunner

	register_for_job_type('archive_it_import_job', :run_concurrently => false)

    include JSONModel
    include JSONModel::HTTP
    include URI

	def run
        begin
            RequestContext.open( :repo_id => @job.repo_id) do
                resource_id = JSONModel.parse_reference(@json.job['resource_uri'])[:id]

                params = JSON.parse(JSON.parse(@job.job_params))

                @backend_url = params['backend']
                @session_key = params['session']

                @collection_url = @json.job['collection_url']
                collection_id = @collection_url.split("/")[-1]
                @resource_uri = @json.job['resource_uri']
                @archival_object_post_uri = "#{@backend_url}/repositories/#{@job.repo_id}/archival_objects"
                @digital_object_post_uri = "#{@backend_url}/repositories/#{@job.repo_id}/digital_objects"

                api_uri = URI("https://partner.archive-it.org/api/seed?collection=#{collection_id}&pluck=id&limit=10000")
                response = Net::HTTP.get(api_uri)

                @seed_ids = JSON.parse(response).map{|seed|
                    seed.to_s
                }

                JSONModel::HTTP.current_backend_session = @session_key


                log("Updating #{@backend_url}#{@resource_uri}")
                log("This will update all seeds with the latest Archive-It data.")
        
                @job.record_created_uris([@resource_uri]) # record_modified_uris doesn't work, so I'm using the next best thing   



                ##########################################################
                # Modify / create all the records
                ##########################################################

                updated_count = 0
                created_count = 0

                records = find_archival_objects(@seed_ids)

                if @seed_ids.length > 0 then
                    log("")
                    log("")
                    log("Updating records from Archive-It...")

                    @seed_ids.map do |seed|

                        if records[seed] then
                            metadata = get_seed_metadata(seed)

                            archival_uri = URI("#{@backend_url}#{records[seed]}")

                            archival_object_response = get_json(archival_uri)
                            archival_object = ASUtils.json_parse(archival_object_response.body)
                            
                            uri = refresh_archival_object(archival_object, seed, metadata, archival_uri)

                            log("    Updated #{uri}")
                            updated_count += 1
                        else
                            uri = create_archival_object(seed)

                            log("    Created #{uri}")
                            created_count += 1
                        end
                    end
                end



                ##########################################################
                # Done! Tell the user what changes were made
                ##########################################################

                redirect_url = @resource_uri.split("/").slice(3, 2).join("/")

                log("")
                log("")
                log("Finished! The resource /#{redirect_url} is updated.")
                log("")
                log("There were:  #{updated_count} old object(s) updated")
                log("             #{created_count} new object(s) created")
                log("")
                log("Please click 'Refresh Page' to view the modified resource.")
        
                self.success!     
            end
        rescue Exception => e
            @job.write_output(e.message)
            @job.write_output(e.backtrace)
            raise e
        end
	end

    def get_json(uri)
        res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http|
            req = Net::HTTP::Get.new(uri)
            req["X-ArchivesSpace-Session"] = @session_key

            http.request(req)
        }

        res
    end

	def log(s)
		Log.debug(s)
		@job.write_output(s)
	end


    def get_seed_metadata(seed_id)
        api_uri = URI("https://partner.archive-it.org/api/seed/#{seed_id}")
        response = Net::HTTP.get(api_uri)

        JSON.parse(response)
    end

    def find_archival_objects(seed_ids)
        hash = {}

        seed_ids.map do |seed|
            uri = URI("#{@backend_url}/repositories/#{@job.repo_id}/find_by_id/archival_objects?component_id[]=#{seed}")

            res = get_json(uri)
            objs = ASUtils.json_parse(res.body)["archival_objects"]

            if objs[0] then
                hash[seed] = objs[0]["ref"]
            end
        end

        hash
    end

    def create_digital_object(seed_metadata)
        wayback_url = "https://wayback.archive-it.org/#{seed_metadata['collection']}/*/#{seed_metadata['url']}"

        digital_object = JSONModel(:digital_object).new._always_valid!
        digital_object.digital_object_id = SecureRandom.hex
        
        # The title value is not final. The refresh function will modify it
        digital_object.title = seed_metadata["url"]
        
        digital_object_response = JSONModel::HTTP::post_json(URI(@digital_object_post_uri), digital_object.to_json)

        result = ASUtils.json_parse(digital_object_response.body)
        digital_object_uri = result["uri"]
        digital_object_uri
    end

    def create_archival_object(seed_id)
        seed_metadata = get_seed_metadata(seed_id)

        if seed_metadata["detail"] == "Not found" then
            raise "seed_not_found:" + seed_id;
        end

        collection_id = seed_metadata["collection"].to_s
        digital_object_uri = create_digital_object(seed_metadata)
        site_url = seed_metadata["url"]


        archival_object = JSONModel(:archival_object).new
        archival_object.instances = [{:instance_type => 'digital_object', :digital_object => {:ref => digital_object_uri}}]

        if true then # These values are not final. They will be overwritten by refresh_archival_object()
            archival_object.resource = {'ref' => @resource_uri}
            archival_object.title = site_url
            archival_object.component_id = seed_id
            archival_object.level = "otherlevel"
            archival_object.other_level = "seed"
        end
        
        refresh_archival_object(ASUtils.json_parse(archival_object.to_json), seed_id, seed_metadata, nil)
    end

    def refresh_archival_object(archival_object, seed_id, seed_metadata, archival_uri)
        if seed_metadata["detail"] == "Not found" then
            raise "seed_not_found:" + seed_id;
        end


        title = seed_metadata['metadata']['Title']
        
        if title != nil then
            title = title[0]['value']
        end


        ##########################################################
        # Update the digital object

        digital_object_uri = "#{@backend_url}#{archival_object['instances'][0]['digital_object']['ref']}"
        digital_object_response = get_json(URI(digital_object_uri))

        digital_object = ASUtils.json_parse(digital_object_response.body)


        wayback_url = "https://wayback.archive-it.org/#{seed_metadata['collection']}/*/#{seed_metadata['url']}"

        digital_object['title'] = seed_metadata["url"]
        digital_object['file_versions'] = [{file_uri: wayback_url, xlink_show_attribute: 'new', xlink_actuate_attribute: 'onRequest', publish: true}]
        digital_object['publish'] = true
        
        if title != nil then
            digital_object['notes'] = [{type: 'note', publish: true, content: ["Website title: #{title}"], jsonmodel_type: 'note_digital_object'}]
        else
            digital_object['notes'] = []
        end

        digital_object_response = JSONModel::HTTP::post_json(URI(digital_object_uri), digital_object.to_json)


        ##########################################################
        # Update the archival object

        archival_object['resource'] = {'ref' => @resource_uri}
        archival_object['title'] = seed_metadata["url"]
        archival_object['component_id'] = seed_id
        archival_object['level'] = "otherlevel"
        archival_object['other_level'] = "seed"



        archival_object['external_documents'] = [{'title' => 'Archive-It URL', 'location' => "#{@collection_url}/seeds/#{seed_id}"}, {'title' => title || "Seed URL", 'location' => "#{seed_metadata['url']}"}]
        


        ##########################################################
        # Save chnages to ArchivesSpace

        archival_uri ||= @archival_object_post_uri
        
        archival_object_response = JSONModel::HTTP::post_json(URI(archival_uri), archival_object.to_json)

        result = ASUtils.json_parse(archival_object_response.body)
        archival_object_uri = result["uri"]

        archival_object_uri
    end
end
