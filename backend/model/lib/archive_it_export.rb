module ArchiveItExport
  include ExportHelpers
  include ASpaceExport

  ASpaceExport::init

  def generate_archive_it_marc(id)
    obj = resolve_references(ArchivalObject.to_jsonmodel(id), ['repository', 'linked_agents', 'subjects'])
    wayback_links_and_earliest_capture = ArchiveIt.get_wayback_links_and_earliest_capture(id)
    wayback_links = wayback_links_and_earliest_capture[:wayback_links]
    earliest_capture = wayback_links_and_earliest_capture[:earliest_capture]
    marc = ASpaceExport.model(:archive_it_marc).from_resource(JSONModel(:archival_object).new(obj), wayback_links, earliest_capture)
    ASpaceExport::serialize(marc)
  end

end