class ArchiveItCollectionMapController < ApplicationController

    set_access_control "view_repository" => [:index, :save_mapping, :get_current_mapping]

    include ExportHelper
    
    def index
        if(params["saved"]) then
            flash.now[:success] = I18n.t("plugins.archive_it.messages.saved")
            params.delete("saved")
        end

        if(params["fix"]) then
            @fix = params["fix"]
        end

        @current_mapping = get_current_mapping
    end

    def save_mapping
        # Parse params and obtain the collection mapping
        rows = {}

        params.each do |key, value|
            if m = key.match(/row(\d+)(\w\w)/) then
                row = rows[m.captures[0]] || {}

                row[m.captures[1]] = value

                rows[m.captures[0]] = row
            end
        end

        mapping = {}

        rows.each do |_, value|
            if value["ai"] != nil && value["as"] != nil && value["ai"] != "" && value["as"] != "" then
                mapping[value["ai"]] = value["as"]
            end
        end


        # Save the mapping to a file
        path = "#{__dir__}/../../archive_it_mapping.json"

        File.open(path, 'w') do |file|
            file.write(mapping.to_json)
        end

        # Refresh the page and show a success banner
        redirect_to "/plugins/archive_it_collection_map?saved=true"
    end

    def get_current_mapping
        JSON.parse(JSONModel::HTTP::get_json("/current_archive_it_mapping"))
    end
end
