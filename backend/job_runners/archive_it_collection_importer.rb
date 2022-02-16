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

                backend_url = params['backend']
                @session_key = params['session']

                @collection_url = @json.job['collection_url']
                collection_id = @collection_url.split("/")[-1]
                @resource_uri = @json.job['resource_uri']
                @archival_object_post_uri = "#{backend_url}/repositories/#{@job.repo_id}/archival_objects"
                @digital_object_post_uri = "#{backend_url}/repositories/#{@job.repo_id}/digital_objects"

                api_uri = URI("https://partner.archive-it.org/api/seed?collection=#{collection_id}&pluck=id&limit=10000")
                response = Net::HTTP.get(api_uri)

                @seed_ids = JSON.parse(response)

                JSONModel::HTTP.current_backend_session = @session_key


                log("Updating #{backend_url}#{@resource_uri}")
                log("This will delete the old objects and recreate them from the latest Archive-It data.")
                log("")
        
                ##########################################################
                # Attempt to load the object tree so that we can delete everything
                ##########################################################
        
                uri = URI("#{backend_url}#{@resource_uri}/tree")
        
                res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http|
                    req = Net::HTTP::Get.new(uri)
                    req["X-ArchivesSpace-Session"] = @session_key
        
                    http.request(req)
                }
        
                if res.code != "200" then
                    log("Unable to access ArchivesSpace resource: #{@resource_uri}")
                    log("")
                    log("Response code: #{res.code}")
                    log("Response body: #{res.body}")
                    return
                end
        
                tree = JSON.parse(res.body)
        
        
        
                ##########################################################
                # Delete all of the old objects
                ##########################################################
        
                log("")
                log("Deleting old records...")
                deleted_count = 0
                
                tree["children"].map{|child|
                    endpoint = "#{@resource_uri.split("/").slice(0, 3).join("/")}/archival_objects/#{child["id"]}"
                    uri = URI("#{backend_url}#{endpoint}")
        
                    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http|
                        req = Net::HTTP::Delete.new(uri)
                        req["X-ArchivesSpace-Session"] = @session_key
        
                        http.request(req)
                    }
        
                    log("    Deleted #{endpoint}")
                    deleted_count += 1
                }
        
        
                
                ##########################################################
                # Now create all the new records
                ##########################################################
        
                created_count = 0
        
                if @seed_ids.length > 0 then
                    log("")
                    log("")
                    log("Now creating new records from Archive-It...")
        
                    @seed_ids.map do |seed|
                        create_archival_object(seed.to_s)
                        created_count += 1
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
                log("There were:  #{deleted_count} old object(s) deleted")
                log("             #{created_count} new object(s) created")
                log("")
                log("Please click 'Refresh Page' to view the modified record.")
        
                @job.record_created_uris([@resource_uri]) # record_modified_uris doesn't work, so I'm using the next best thing   

                self.success!     
            end
        rescue Exception => e
            @job.write_output(e.message)
            @job.write_output(e.backtrace)
            raise e
        end
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

    def create_digital_object(seed_metadata)
        wayback_url = "https://wayback.archive-it.org/#{seed_metadata['collection']}/*/#{seed_metadata['url']}"
        digital_object = JSONModel(:digital_object).new._always_valid!
        digital_object.title = seed_metadata["url"]
        digital_object.digital_object_id = SecureRandom.hex
        digital_object.file_versions = [{:file_uri => wayback_url, :xlink_show_attribute => 'new', :xlink_actuate_attribute => 'onRequest'}]
        digital_object.notes = [{:type => 'note', :publish => true, :content => ['view captures'], :jsonmodel_type => 'note_digital_object'}]
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


        archival_object = JSONModel(:archival_object).new._always_valid!

        archival_object.resource = {'ref' => @resource_uri}
        archival_object.title = site_url
        archival_object.component_id = seed_id
        archival_object.level = "otherlevel"
        archival_object.other_level = "seed"
        archival_object.instances = [{:instance_type => 'digital_object', :digital_object => {:ref => digital_object_uri}}]

        archival_object.external_documents = [{:title => 'Archive-It URL', :location => "#{@collection_url}/seeds/#{seed_id}"}, {:title => 'Seed URL', :location => "#{seed_metadata['url']}"}]
        
        archival_object_response = JSONModel::HTTP::post_json(URI(@archival_object_post_uri), archival_object.to_json)
        
        result = ASUtils.json_parse(archival_object_response.body)
        archival_object_uri = result["uri"]

        log("    Created #{archival_object_uri}")

        archival_object_uri
    end

end
