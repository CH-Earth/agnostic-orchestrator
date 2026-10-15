def parse_args($array):
    [
        ($array | to_entries[] | 
            if (.key == "_flags") then
                select((.value | type == "array") and (.value | length != 0)) |
                .value | map("--" + .) | join(" ") + " "
            elif (.key == "_arguments") then
                empty  # Skip here, we'll handle it later
            else
                select(.value != "") |
                if (.value | type == "array") then
                    "--" + .key + "=" + (.value | join(",")) + " " 
                else
                    "--" + .key + "=" + (.value) + " " 
                end 
            end),
        ($array._arguments // [] | join(" "))
    ] | join("") | rtrimstr(" ");

def count($array):
  array | length
  ;

def select_independants($array):
  array |
  to_entries | .[] | 
  select((.value == -1) or (.value == "-1")) |
  .key
  ;

def select_dependants($array):
  array |
  to_entries |
  map(select(.value > 0)) |
  sort_by(.value) |
  .[].key
  ;
