$(function() {
    var add_archive_it_link = function() {
        var $archival_object_id = get_object_info();
        if ($archival_object_id) {
            var $download_url = '/plugins/archive_it/' + $archival_object_id + '/download_marc?id=' + $archival_object_id;
            var $dropdown_menu = $("#other-dropdown");
            if ($dropdown_menu.length == 1) {
                var $archive_it = $("<li><a href='" + $download_url + "'>Web Archives - Export MARCXML</a></li>");
                $dropdown_menu.find("ul.dropdown-menu").append($archive_it);
            };
        };
    }

    var get_object_info = function() {
        var $obj_form = $("#archival_object_form");
        if ($obj_form.length > 0) {
            return $obj_form.find("#id").val();
        }
        else {
            return false;
        }
    };

    $(document).on('loadedrecordform.aspace', function() {
        add_archive_it_link();
    });

});