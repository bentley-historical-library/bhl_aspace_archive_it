require 'json'
require 'net/http'
require 'securerandom'

class ArchiveItImporter

    def initialize(seed_url, session)
        @repo_id = session[:repo_id]

        archival_object_post_uri = "#{JSONModel::HTTP.backend_url}/repositories/#{@repo_id}/archival_objects"
        digital_object_post_uri = "#{JSONModel::HTTP.backend_url}/repositories/#{@repo_id}/digital_objects"
        archive_it_mapping = JSON.parse(JSONModel::HTTP::get_json("/current_archive_it_mapping"))

        @session = session
        @seed_url = seed_url

        url_components = seed_url.split("/")

        if url_components[-2] == "seeds" then
            @seed_ids = [url_components[-1]]
            @collection_id = url_components[-3]
            @one_seed = true
        else
            @collection_id = url_components[-1]

            @seed_ids = get_seeds_in_collection(@collection_id).map(&:to_s)
            
            if @seed_ids == [] then
                raise "collection_not_found:#{@collection_id}"
            end
        end

        if (not archive_it_mapping.key?(@collection_id) ) || archive_it_mapping[@collection_id] == "" then
            raise "no_mapping:" + @collection_id
        end

        resource_id = archive_it_mapping[@collection_id]

        # Find collection uri
        search = JSONModel::HTTP::get_json("/search?q=#{resource_id}&fields[]=identifier,uri&type[]=resource&page=1&page_size=1")
        
        if search == nil then
            @resource_uri = JSONModel(:resource).uri_for(resource_id)
        else
            raise "no_resource:#{@collection_id}:#{resource_id}"
        end

        # Check if the mapped resource is present in ArchivesSpace
        # Todo: Is this unnecessary from the code above?
        begin
            resource = JSONModel::HTTP::get_json(JSONModel(:resource).uri_for(resource_id))
            if resource == nil then
                raise ""
            end
        rescue Exception => ex
            raise "no_resource:#{@collection_id}:#{resource_id}"
        end

        @archival_object_post_uri = archival_object_post_uri
        @digital_object_post_uri = digital_object_post_uri
    end

    def get_seeds_in_collection(collection_id)
        api_uri = URI("https://partner.archive-it.org/api/seed?collection=#{collection_id}&pluck=id&limit=10000")
        response = Net::HTTP.get(api_uri)

        JSON.parse(response)
    end



    def find_archival_objects(seed_ids)
        hash = {}

        seed_ids.map do |seed|

            # I could not get  JSONModel::HTTP::get_json("/repositories/#{@repo_id}/find_by_id/archival_objects?component_id[]=#{seed}")  to work

            uri = URI("#{JSONModel::HTTP.backend_url}/repositories/#{@repo_id}/find_by_id/archival_objects?component_id[]=#{seed}")

            res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http|
                req = Net::HTTP::Get.new(uri)
                req["X-ArchivesSpace-Session"] = @session[:session]

                http.request(req)
            }
            objs = ASUtils.json_parse(res.body)["archival_objects"]

            if objs[0] then
                hash[seed] = objs[0]["ref"]
            end
        end

        hash
    end

    def get_seed_metadata(seed_id)
        api_uri = URI("https://partner.archive-it.org/api/seed/#{seed_id}")
        response = Net::HTTP.get(api_uri)

        JSON.parse(response)
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

        digital_uri = archival_object['instances'][0]['digital_object']['ref']
        digital_object = JSONModel::HTTP::get_json(digital_uri)

        wayback_url = "https://wayback.archive-it.org/#{seed_metadata['collection']}/*/#{seed_metadata['url']}"

        digital_object['title'] = seed_metadata["url"]
        digital_object['file_versions'] = [{file_uri: wayback_url, xlink_show_attribute: 'new', xlink_actuate_attribute: 'onRequest', publish: true}]
        digital_object['publish'] = true
        
        if title != nil then
            digital_object['notes'] = [{type: 'note', publish: true, content: ["Website title: #{title}"], jsonmodel_type: 'note_digital_object'}]
        else
            digital_object['notes'] = []
        end

        digital_object_response = JSONModel::HTTP::post_json(URI("#{JSONModel::HTTP.backend_url}#{digital_uri}"), digital_object.to_json)



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

    def create_archival_objects

        if @one_seed then
            seed = @seed_ids[0]

            records = find_archival_objects(@seed_ids)
            record_uri = records[seed]

            if record_uri then
                metadata = get_seed_metadata(seed)

                archival_object = JSONModel::HTTP::get_json(URI(records[seed]))

                archival_uri = "#{JSONModel::HTTP::backend_url}#{records[seed]}"
                return Resolver.new(refresh_archival_object(archival_object, seed, metadata, archival_uri)).view_uri
            else
                return Resolver.new(create_archival_object(seed)).view_uri
            end
        end


        # If importing multiple seeds, make a background job

        job_type = 'archive_it_import_job'
        job_data = {'jsonmodel_type' => job_type}
        
        job_data['collection_url'] = @seed_url
        job_data['resource_uri'] = @resource_uri

        job = Job.new(job_type, job_data, [], {
            :backend => JSONModel::HTTP::backend_url,
            :session => @session[:session]
        })
        uploaded = job.upload


        parts = uploaded['uri'].split('/');
        return "/#{parts[3]}/#{parts[4]}"

    end

end