class ArchiveItController < JobsController

    set_access_control "view_repository" => [:index, :import, :download_marc]
    alias_method :create_job, :create

    include ExportHelper
    
    def index
        if params["error"] then
            p params["error"]
            error, id, id2 = params["error"].split(':')

            errorMessage = I18n.t("plugins.archive_it.errors.#{error}")

            flash.now[:error] = eval("\"#{errorMessage}\"".gsub(/\\/, ""))

            if error == "no_mapping" || error = "no_resource" then
                @fix_collection = id
            end
        else
      	    flash.now[:info] = I18n.t("plugins.archive_it.messages.service_notice")
        end
    end

    def download_marc
        download_archive_it_export(
            "/repositories/#{JSONModel::repository}/archive_it/archive_it_marc/#{params[:id]}.xml")
    end

    def import
        seed_url = params["seed_url"]

        begin
            importer = ArchiveItImporter.new(seed_url, session)

            redirect_url, isCreated = importer.create_archival_objects

        rescue Exception => ex
            redirect_url = "/plugins/archive_it?error=#{ex.message}"
        end

        redirect_to redirect_url
        
        if isCreated then
            flash[:success] = I18n.t("plugins.archive_it.messages.seed_created")
        elsif isCreated == false then
            flash[:success] = I18n.t("plugins.archive_it.messages.seed_overwritten")
        end
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
