class ArchiveIt

    def self.get_marc_candidates
        DB.open do |db|
            # find site-level archival objects that have creators that do not show up in any other non web archives resources
            creator_enum_id = db[:enumeration].filter(:name=>'linked_agent_role').join(:enumeration_value, :enumeration_id => Sequel.qualify(:enumeration, :id)).where(:value => 'creator').all[0][:id]
            # Get an array of archival object ids for site-level archival objects
            site_ids = ArchivalObject.filter(:other_level=>'seed').exclude(:parent_id => nil).map(:parent_id).uniq
            # Get arrays of agent ids that are linked to site-level archival objects
            person_creators = db[:linked_agents_rlshp].filter({:archival_object_id => site_ids, :role_id => creator_enum_id}).exclude(:agent_person_id => nil).map(:agent_person_id).uniq
            corporate_creators = db[:linked_agents_rlshp].filter({:archival_object_id => site_ids, :role_id => creator_enum_id}).exclude(:agent_corporate_entity_id => nil).map(:agent_corporate_entity_id).uniq
            # Get arrays of agent ids that are linked to an existing resource
            resource_linked_people = db[:linked_agents_rlshp].filter(:agent_person_id => person_creators).exclude(:resource_id => nil).map(:agent_person_id).uniq
            resource_linked_corps = db[:linked_agents_rlshp].filter(:agent_corporate_entity_id => corporate_creators).exclude(:resource_id => nil).map(:agent_corporate_entity_id).uniq
            # Get arrays of agents that are linked as creators from site-level archival objects but which are not associated with any resources
            unique_people = person_creators - resource_linked_people
            unique_corps = corporate_creators - resource_linked_corps
            # Get an array of archival object ids that are site-level archival objects and have a creator that is not associated with any resources
            unique_sites = db[:linked_agents_rlshp].filter(:archival_object_id => site_ids).where(:agent_person_id => unique_people).or(:agent_corporate_entity_id => unique_corps).map(:archival_object_id).uniq
            unique_sites
        end
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