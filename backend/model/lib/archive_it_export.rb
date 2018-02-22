module ArchiveItExport
  include ExportHelpers
  include ASpaceExport

  ASpaceExport::init

  def generate_archive_it_marc(id)
    obj = resolve_references(ArchivalObject.to_jsonmodel(id), ['repository', 'linked_agents', 'subjects'])
    wayback_links = ArchiveIt.get_wayback_links(id)
    marc = ASpaceExport.model(:archive_it_marc).from_resource(JSONModel(:archival_object).new(obj), wayback_links)
    ASpaceExport::serialize(marc)
  end

end