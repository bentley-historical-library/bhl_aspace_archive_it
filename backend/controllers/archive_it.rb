require_relative "../model/lib/archive_it_export"
class ArchivesSpaceService < Sinatra::Base
  include ArchiveItExport

  Endpoint.get('/repositories/:repo_id/archive_it/marc_candidates')
    .description("Get a list of MARC record candidates")
    .params(["repo_id", :repo_id])
    .permissions(["view_repository"])
    .returns([200, "OK"]) \
  do
    candidates = ArchiveIt.get_marc_candidates

    json_response(:results => candidates)
  end

  Endpoint.get('/repositories/:repo_id/archive_it/archive_it_collections')
    .description("Get a mapping of Archive-It collections and ArchivesSpace Resources")
    .params(["repo_id", :repo_id])
    .permissions(["view_repository"])
    .returns([200, "OK"]) \
  do
    collection_resource_map = ArchiveIt.get_archive_it_collection_map

    json_response(collection_resource_map)
  end

  Endpoint.get('/repositories/:repo_id/archive_it/wayback_links_site/:id')
    .description("Get a list of wayback URLs for a given site-level Archival Object")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions(["view_repository"])
    .returns([200, "OK"]) \
  do
    wayback_links = ArchiveIt.get_wayback_links(params[:id])

    json_response(:results => wayback_links)
  end

  Endpoint.get('/repositories/:repo_id/archive_it/archive_it_marc/:id.xml')
    .description("Get a MARC 21 representation of a site-level Archival Object")
    .params(["id", :id],
            ["repo_id", :repo_id])
    .permissions([:view_repository])
    .returns([200, "(:resource)"]) \
  do
    marc = generate_archive_it_marc(params[:id])

    xml_response(marc)
  end
end