class ArchiveIt

    def self.get_marc_candidates
        site_ids = ArchivalObject.filter(:other_level => 'seed').exclude(:parent_id => nil).map(:parent_id).uniq
    end

    def self.get_wayback_links_and_earliest_capture(site_id)
        wayback_links = []
        earliest_date = ""
        seed_ids = ArchivalObject.filter(:parent_id => site_id).map(:id)
        seed_ids.each do |seed_id|
            seed = URIResolver.resolve_references(ArchivalObject.to_jsonmodel(seed_id), ['digital_object'])
            json = JSONModel::JSONModel(:archival_object).new(seed)
            digital_object_instances = json.instances.select{|inst| inst['digital_object']}.compact
            digital_object_instances.each do |instance|
                file_versions = instance["digital_object"]["_resolved"]["file_versions"]
                file_versions.each do |file_version|
                    link = file_version["file_uri"]
                    wayback_links << link
                end
            end
            json.dates.each do |date|
                begin_year = date["begin"].split("-")[0]
                if earliest_date.empty? | (begin_year < earliest_date)
                    earliest_date = begin_year
                end
            end
        end
        earliest_capture = earliest_date.empty? ? false : earliest_date
        {:wayback_links => wayback_links, :earliest_capture => earliest_capture}
    end

    def self.get_archive_it_collection_resources
        archive_it_resources = Resource.exclude(:ead_id => nil).where(Sequel.like(:title, '%Web Archives%')).to_hash(:ead_id, :id)
        collection_resource_map = {}
        archive_it_resources.each do |ead_id, resource_id|
            archive_it_collection = ead_id.split("-")[-1]
            collection_resource_map[archive_it_collection] = resource_id
        end
        collection_resource_map
    end

end