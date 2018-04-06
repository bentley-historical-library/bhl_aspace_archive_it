require 'json'
require 'net/http'
require 'securerandom'

class ArchiveItImporter
    def initialize(seed_url, archival_object_post_uri, digital_object_post_uri, collection_resource_map_uri)
        @seed_url = seed_url
        @seed_id = seed_url.split("/")[-1]
        @archival_object_post_uri = archival_object_post_uri
        @digital_object_post_uri = digital_object_post_uri
        @collection_resource_map_uri = collection_resource_map_uri
    end

    def get_seed_metadata
        api_url = "https://partner.archive-it.org/api/seed/#{@seed_id}"
        api_uri = URI(api_url)
        response = Net::HTTP.get(api_uri)
        JSON.parse(response)
    end

    def create_digital_object
        wayback_url = "https://wayback.archive-it.org/#{@seed_metadata['collection']}/*/#{@seed_metadata['url']}"
        digital_object = JSONModel(:digital_object).new._always_valid!
        digital_object.title = @seed_metadata["url"]
        digital_object.digital_object_id = SecureRandom.hex
        digital_object.file_versions = [{:file_uri => wayback_url, :xlink_show_attribute => 'new', :xlink_actuate_attribute => 'onRequest'}]
        digital_object.notes = [{:type => 'note', :publish => true, :content => ['view captures'], :jsonmodel_type => 'note_digital_object'}]
        digital_object_response = JSONModel::HTTP::post_json(URI(@digital_object_post_uri), digital_object.to_json)
        result = ASUtils.json_parse(digital_object_response.body)
        digital_object_uri = result["uri"]
        digital_object_uri
    end

    def create_archival_object
        @seed_metadata = get_seed_metadata
        collection_resource_map = JSONModel::HTTP::get_json(URI(@collection_resource_map_uri))
        collection_id = @seed_metadata["collection"].to_s
        resource_id = collection_resource_map[collection_id]
        $stderr.puts("#{@seed_metadata}")
        digital_object_uri = create_digital_object
        site_url = @seed_metadata["url"]
        archival_object = JSONModel(:archival_object).new._always_valid!
        archival_object.resource = {'ref' => JSONModel(:resource).uri_for(resource_id)}
        archival_object.title = site_url
        archival_object.component_id = @seed_id
        archival_object.level = "otherlevel"
        archival_object.other_level = "seed"
        archival_object.instances = [{:instance_type => 'digital_object', :digital_object => {:ref => digital_object_uri}}]
        archival_object.external_documents = [{:title => 'Archive-It URL', :location => @seed_url}, {:title => 'Seed URL', :location => "#{@seed_metadata['url']}"}]
        archival_object_response = JSONModel::HTTP::post_json(URI(@archival_object_post_uri), archival_object.to_json)
        result = ASUtils.json_parse(archival_object_response.body)
        archival_object_uri = result["uri"]
        archival_object_uri
    end

end