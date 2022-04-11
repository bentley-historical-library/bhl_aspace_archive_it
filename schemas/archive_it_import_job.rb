{
  :schema => {
    "$schema" => "http://www.archivesspace.org/archivesspace.json",
    "version" => 1,
    "type" => "object",

    "properties" => {
      
      "collection_url" => {
        "type" => "string",
        "ifmissing" => "error"
      },
      "resource_uri" => {
        "type" => "string",
        "ifmissing" => "error"
      },
    }
  }
}
