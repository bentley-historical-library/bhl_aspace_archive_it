class ArchiveItController < ApplicationController

    set_access_control "view_repository" => [:index, :import, :download_marc]

    include ExportHelper
    
    def index
    end

    def download_marc
        download_archive_it_export(
            "/repositories/#{JSONModel::repository}/archive_it/archive_it_marc/#{params[:id]}.xml")
    end

    def import
        seed_url = params["seed_url"]
        archival_object_post_uri = "#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/archival_objects"
        digital_object_post_uri = "#{JSONModel::HTTP.backend_url}/repositories/#{session[:repo_id]}/digital_objects"
        collection_resource_map_uri = "/repositories/#{session[:repo_id]}/archive_it/archive_it_collections"
        importer = ArchiveItImporter.new(seed_url, archival_object_post_uri, digital_object_post_uri, collection_resource_map_uri)
        archival_object_uri = importer.create_archival_object
        resolver = Resolver.new(archival_object_uri)
        redirect_to resolver.view_uri
    end

    private

    def download_archive_it_export(request_uri, params = {})
        meta = {}
        meta["mimtype"] = "application/xml"
        meta["filename"] = "archive_it_marc.xml"

        respond_to do |format|
          format.html {
            self.response.headers["Content-Type"] = meta['mimetype'] if meta['mimetype']
            self.response.headers["Content-Disposition"] = "attachment; filename=#{meta['filename']}"
            self.response.headers['Last-Modified'] = Time.now.ctime.to_s

            self.response_body = Enumerator.new do |y|
              xml_response(request_uri, params) do |chunk, percent|
                y << chunk if !chunk.blank?
              end
            end
          }
        end
    end

end
