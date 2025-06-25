# frozen_string_literal: true

require "pagy"

# Pagy initializer file (6.0.0)
# Customize only what you really need and notice that the core Pagy works also without any of the following lines.

# Instance variables
# See https://ddnexus.github.io/pagy/docs/api/pagy#instance-variables
Pagy::DEFAULT[:limit] = 20                                  # default items per page
Pagy::DEFAULT[:size]  = 9                                   # default nav bar links
# Pagy::DEFAULT[:ends]  = true                              # default for showing/hiding first and last links
# Pagy::DEFAULT[:cycle] = false                             # default for cycling through the pages

# Other Variables
# See https://ddnexus.github.io/pagy/docs/api/pagy#other-variables
# Pagy::DEFAULT[:page_param] = :page                        # default parameter name
# Pagy::DEFAULT[:limit_param] = :limit                      # default parameter name
# Pagy::DEFAULT[:fragment] = '#fragment'                    # example
# Pagy::DEFAULT[:link_extra] = 'data-turbo-action="advance"'  # example
# Pagy::DEFAULT[:i18n_key] = 'pagy.item_name'               # default
# Pagy::DEFAULT[:cycle] = false                             # example
# Pagy::DEFAULT[:request_path] = "/foo"                     # example

# Extras
# See https://ddnexus.github.io/pagy/categories/extra

# Backend Extras

# Arel: For better performance utilizing grouped ActiveRecord collections
# See https://ddnexus.github.io/pagy/docs/extras/arel
# require 'pagy/extras/arel'

# Array: Paginate arrays efficiently, avoiding expensive array-wrapping and without overriding
# See https://ddnexus.github.io/pagy/docs/extras/array
# require 'pagy/extras/array'

# Calendar: Add pagination filtering by calendar time unit (year, quarter, month, week, day)
# See https://ddnexus.github.io/pagy/docs/extras/calendar
# require 'pagy/extras/calendar'
# Default for each unit
# Pagy::Calendar::Year::DEFAULT[:order]     = :asc        # Time direction of pagination
# Pagy::Calendar::Quarter::DEFAULT[:order]  = :asc        # Time direction of pagination
# Pagy::Calendar::Month::DEFAULT[:order]    = :asc        # Time direction of pagination
# Pagy::Calendar::Week::DEFAULT[:order]     = :asc        # Time direction of pagination
# Pagy::Calendar::Day::DEFAULT[:order]      = :asc        # Time direction of pagination
# Pagy::Calendar::Year::DEFAULT[:format]    = '%Y'        # strftime format
# Pagy::Calendar::Quarter::DEFAULT[:format] = '%Y-Q%q'    # strftime format
# Pagy::Calendar::Month::DEFAULT[:format]   = '%Y-%m'     # strftime format
# Pagy::Calendar::Week::DEFAULT[:format]    = '%Y-%W'     # strftime format
# Pagy::Calendar::Day::DEFAULT[:format]     = '%Y-%m-%d'  # strftime format
# Uncomment the following lines, if you need calendar localization without using the I18n extra
# module LocalizePagyCalendar
#   def localize(time, opts)
#     ::I18n.l(time, **opts)
#   end
# end
# Pagy::Calendar.prepend LocalizePagyCalendar

# Countless: Paginate without any count, saving one query per rendering
# See https://ddnexus.github.io/pagy/docs/extras/countless
# require 'pagy/extras/countless'
# Pagy::DEFAULT[:countless_minimal] = false               # default (eager loading)

# Headers: http response headers (and other helpers) useful for API pagination
# See https://ddnexus.github.io/pagy/docs/extras/headers
# require 'pagy/extras/headers'
# Pagy::DEFAULT[:headers] = { page: 'Current-Page',
#                            limit: 'Page-Items',
#                            count: 'Total-Count',
#                            pages: 'Total-Pages' }     # default

# Metadata: Provides the pagination metadata to Javascript frameworks like Vue.js, react.js, etc.
# See https://ddnexus.github.io/pagy/docs/extras/metadata
# you must require the frontend helpers internal extra (BEFORE the metadata extra) ONLY if you need also the :sequels
# require 'pagy/extras/frontend_helpers'
# require 'pagy/extras/metadata'
# For performance reasons, you should explicitly set ONLY the metadata you use in the frontend
# Pagy::DEFAULT[:metadata] = %i[scaffold_url page prev next last]   # example

# Frontend Extras

# Bootstrap: Nav, nav_js and combo_nav_js helpers and templates for Bootstrap pagination
# See https://ddnexus.github.io/pagy/docs/extras/bootstrap
# require 'pagy/extras/bootstrap'

# Bulma: Nav, nav_js and combo_nav_js helpers and templates for Bulma pagination
# See https://ddnexus.github.io/pagy/docs/extras/bulma
# require 'pagy/extras/bulma'

# Pagy Variables
# See https://ddnexus.github.io/pagy/docs/api/pagy#variables
# All the Pagy::DEFAULT are set for all the Pagy instances but can be overridden per instance by just passing them to
# Pagy.new|Pagy::Countless.new|Pagy::Calendar::*.new or any of the #pagy* controller methods

# Rails
# Rails: extras assets path required by the helpers that use javascript
# (pagy*_nav_js, pagy*_combo_nav_js, and pagy_items_selector_js)
# See https://ddnexus.github.io/pagy/docs/api/javascript
# Rails.application.config.assets.paths << Pagy.root.join('javascripts') # uncomment if you use the asset pipeline
# Searchkick: Paginate `Searchkick::Results` objects
# See https://ddnexus.github.io/pagy/docs/extras/searchkick
# require 'pagy/extras/searchkick'
# Pagy::DEFAULT[:searchkick_search_method] = :pagy_search
# Pagy::DEFAULT[:searchkick_pagy_method]   = :pagy_searchkick

# Frontend i18n: All the available locales are loaded upfront, so you can use them with Pagy::I18n.load
# (even without the i18n extra below)
# See https://ddnexus.github.io/pagy/docs/api/i18n
# Notice: if you opt-in for the I18n extra below, you should explicitly opt-out of the
# Pagy::I18n.load by setting the Pagy::I18n.load to an empty hash
# Pagy::I18n.load = {}

# I18n: Enable the i18n extra for translations
# See https://ddnexus.github.io/pagy/docs/extras/i18n
# Default i18n key
# Pagy::DEFAULT[:i18n_key] = 'pagy.item_name'   # default
# require 'pagy/extras/i18n'

# When you are done setting your own default freeze it, so it will not get changed accidentally
Pagy::DEFAULT.freeze
