module ArchiveItExport
  include ExportHelpers
  include ASpaceExport

  ASpaceExport::init

  def generate_archive_it_marc(id)
    obj = resolve_references(ArchivalObject.to_jsonmodel(id), ['repository', 'linked_agents', 'subjects'])
    wayback_links_and_inclusive_dates = ArchiveIt.get_wayback_links_and_inclusive_dates(id)
    wayback_links = wayback_links_and_inclusive_dates[:wayback_links]
    inclusive_dates = wayback_links_and_inclusive_dates[:inclusive_dates]
    marc = ASpaceExport.model(:archive_it_marc).from_resource(JSONModel(:archival_object).new(obj), wayback_links, inclusive_dates)
    ASpaceExport::serialize(marc)
  end

end