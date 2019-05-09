local declarative = require("kong.db.declarative")
local reports = require("kong.reports")
local errors = require("kong.db.errors")
local kong = kong
local dc = declarative.new_config(kong.configuration)


-- Do not accept Lua configurations from the Admin API
-- because it is Turing-complete.
local accept = {
  yaml = true,
  json = true,
}

local _reports = {
  decl_fmt_version = false,
}


return {
  ["/config"] = {
    POST = function(self, db)
      if kong.db.strategy ~= "off" then
        return kong.response.exit(400, {
          message = "this endpoint is only available when Kong is " ..
                    "configured to not use a database"
        })
      end

      local check_hash, old_hash
      if tostring(self.params.check_hash) == "1" then
        check_hash = true
        old_hash = declarative.get_current_hash()
      end
      self.params.check_hash = nil

      local entities, _, err_t, vers, new_hash
      if self.params._format_version then
        entities, _, err_t, vers, new_hash = dc:parse_table(self.params)
      else
      local config = self.params.config
        entities, _, err_t, vers, new_hash =
          dc:parse_string(config, nil, accept, old_hash)
      end

      if check_hash and new_hash and old_hash == new_hash then
        return kong.response.exit(304)
      end

      if not entities then
        return kong.response.exit(400, errors:declarative_config(err_t))
      end

      local ok, err = declarative.load_into_cache_with_events(entities, new_hash)
      if not ok then
        kong.log.err("failed loading declarative config into cache: ", err)
        return kong.response.exit(500, { message = "An unexpected error occurred" })
      end

      _reports.decl_fmt_version = vers
      reports.send("dbless-reconfigure", _reports)

      return kong.response.exit(201, entities)
    end,
  },
}
