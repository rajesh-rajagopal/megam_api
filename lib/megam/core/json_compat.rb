#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Wrapper class for interacting with JSON.

require "ffi_yajl"
# We're requiring this to prevent breaking consumers using Hash.to_json
require "json"

module Megam
    class JSONCompat
        JSON_MAX_NESTING = 1000


        JSON_CLAZ = 'json_claz'.freeze

        MEGAM_ACCOUNT                     = 'Megam::Account'.freeze
        MEGAM_ASSEMBLIES                  = 'Megam::Assemblies'.freeze
        MEGAM_ASSEMBLIESCOLLECTION        = 'Megam::AssembliesCollection'.freeze
        MEGAM_ASSEMBLY                    = 'Megam::Assembly'.freeze
        MEGAM_ASSEMBLYCOLLECTION          = 'Megam::AssemblyCollection'.freeze
        MEGAM_BALANCES                    = 'Megam::Balances'.freeze
        MEGAM_BALANCESCOLLECTION          = 'Megam::BalancesCollection'.freeze
        MEGAM_BILLEDHISTORIES             = 'Megam::Billedhistories'.freeze
        MEGAM_BILLEDHISTORIESCOLLECTION   = 'Megam::BilledhistoriesCollection'.freeze
        MEGAM_BILLINGTRANSCATIONS             = 'Megam::Billingtranscations'.freeze
        MEGAM_BILLINGTRANSCATIONSCOLLECTION   = 'Megam::BillingtranscationsCollection'.freeze
        MEGAM_COMPONENTS                  = 'Megam::Components'.freeze
        MEGAM_COMPONENTSCOLLECTION        = 'Megam::ComponentsCollection'.freeze
        MEGAM_DOMAIN                      = 'Megam::Domains'.freeze
        MEGAM_DOMAINCOLLECTION            = 'Megam::DomainsCollection'.freeze
        MEGAM_ERROR                       = 'Megam::Error'.freeze
        MEGAM_MARKETPLACE                 = 'Megam::MarketPlace'.freeze
        MEGAM_MARKETPLACECOLLECTION       = 'Megam::MarketPlaceCollection'.freeze
        MEGAM_ORGANIZATION                = 'Megam::Organizations'.freeze
        MEGAM_ORGANIZATIONSCOLLECTION     = 'Megam::OrganizationsCollection'.freeze
        MEGAM_REQUEST                     = 'Megam::Request'.freeze
        MEGAM_REQUESTCOLLECTION           = 'Megam::RequestCollection'.freeze
        MEGAM_SENSORS                     = 'Megam::Sensors'.freeze
        MEGAM_SENSORSCOLLECTION           = 'Megam::SensorsCollection'.freeze
        MEGAM_SNAPSHOTS                     = 'Megam::Snapshots'.freeze
        MEGAM_SNAPSHOTSCOLLECTION           = 'Megam::SnapshotsCollection'.freeze
        MEGAM_SSHKEY                      = 'Megam::SshKey'.freeze
        MEGAM_SSHKEYCOLLECTION            = 'Megam::SshKeyCollection'.freeze
        MEGAM_EVENTSVM                    = 'Megam::EventsVm'.freeze
        MEGAM_EVENTSVMCOLLECTION            = 'Megam::EventsVmCollection'.freeze
        MEGAM_EVENTSCONTAINER             = 'Megam::EventsContainer'.freeze
        MEGAM_EVENTSCONTAINERCOLLECTION   = 'Megam::EventsContainerCollection'.freeze
        MEGAM_EVENTSBILLING               = 'Megam::EventsBilling'.freeze
        MEGAM_EVENTSBILLINGCOLLECTION     = 'Megam::EventsBillingCollection'.freeze
        MEGAM_EVENTSSTORAGE               = 'Megam::EventsStorage'.freeze
        MEGAM_EVENTSSTORAGECOLLECTION     = 'Megam::EventsStorageCollection'.freeze
        MEGAM_PROMOS                      = 'Megam::Promos'.freeze

        class <<self
            # API to use to avoid create_addtions
            def parse(source, opts = {})
                begin
                    FFI_Yajl::Parser.parse(source, opts)
                rescue FFI_Yajl::ParseError => e
                    raise JSON::ParseError, e.message
                end
            end

            # Just call the JSON gem's parse method with a modified :max_nesting field
            def from_json(source, opts = {})
                obj = parse(source, opts)

                # JSON gem requires top level object to be a Hash or Array (otherwise
                # you get the "must contain two octets" error). Yajl doesn't impose the
                # same limitation. For compatibility, we re-impose this condition.
                unless obj.kind_of?(Hash) || obj.kind_of?(Array)
                    raise JSON::ParseError, "Top level JSON object must be a Hash or Array. (actual: #{obj.class})"
                end

                # The old default in the json gem (which we are mimicing because we
                # sadly rely on this misfeature) is to "create additions" i.e., convert
                # JSON objects into ruby objects. Explicit :create_additions => false
                # is required to turn it off.
                if opts[:create_additions].nil? || opts[:create_additions]
                    map_to_rb_obj(obj)
                else
                    obj
                end
            end

            # Look at an object that's a basic type (from json parse) and convert it
            # to an instance of Chef classes if desired.
            def map_to_rb_obj(json_obj)
                case json_obj
                when Hash
                    mapped_hash = map_hash_to_rb_obj(json_obj)
                    if json_obj.has_key?(JSON_CLAZ) && (class_to_inflate = class_for_json_class(json_obj[JSON_CLAZ]))
                        class_to_inflate.json_create(mapped_hash)
                    else
                        mapped_hash
                    end
                when Array
                    json_obj.map { |e| map_to_rb_obj(e) }
                else
                    json_obj
                end
            end

            def map_hash_to_rb_obj(json_hash)
                json_hash.each do |key, value|
                    json_hash[key] = map_to_rb_obj(value)
                end
                json_hash
            end

            def to_json(obj, opts = nil)
                begin
                    FFI_Yajl::Encoder.encode(obj, opts)
                rescue FFI_Yajl::EncodeError => e
                    raise JSON::GeneratorError, e.message
                end
            end


            def to_json_pretty(obj, opts = nil)
                opts ||= {}
                options_map = {}
                options_map[:pretty] = true
                options_map[:indent] = opts[:indent] if opts.has_key?(:indent)
                to_json(obj, options_map).chomp
            end


            # Map +JSON_CLAZ+ to a Class object. We use a +case+ instead of a Hash
            # assigned to a constant because otherwise this file could not be loaded
            # until all the constants were defined, which means you'd have to load
            # the world to get json.
            def class_for_json_class(json_class)
                case json_class
                when MEGAM_ERROR
                    Megam::Error
                when MEGAM_ACCOUNT
                    Megam::Account
                when MEGAM_ASSEMBLIES
                    Megam::Assemblies
                when MEGAM_ASSEMBLIESCOLLECTION
                    Megam::AssembliesCollection
                when MEGAM_ASSEMBLY
                    Megam::Assembly
                when MEGAM_ASSEMBLYCOLLECTION
                    Megam::AssemblyCollection
                when MEGAM_COMPONENTS
                    Megam::Components
                when MEGAM_COMPONENTSCOLLECTION
                    Megam::ComponentsCollection
                when MEGAM_REQUEST
                    Megam::Request
                when MEGAM_REQUESTCOLLECTION
                    Megam::RequestCollection
                when MEGAM_SSHKEY
                    Megam::SshKey
                when MEGAM_SSHKEYCOLLECTION
                    Megam::SshKeyCollection
                  when MEGAM_EVENTSVM
                      Megam::EventsVm
                when MEGAM_EVENTSVMCOLLECTION
                      Megam::EventsVmCollection
                  when MEGAM_EVENTSCONTAINER
                      Megam::EventsContainer
                when MEGAM_EVENTSCONTAINERCOLLECTION
                      Megam::EventsContainerCollection
                    when MEGAM_EVENTSBILLING
                        Megam::EventsBilling
                  when MEGAM_EVENTSBILLINGCOLLECTION
                        Megam::EventsBillingCollection
                      when MEGAM_EVENTSSTORAGE
                          Megam::EventsStorage
                    when MEGAM_EVENTSSTORAGECOLLECTION
                          Megam::EventsStorageCollection
                when MEGAM_MARKETPLACE
                    Megam::MarketPlace
                when MEGAM_MARKETPLACECOLLECTION
                    Megam::MarketPlaceCollection
                when MEGAM_ORGANIZATION
                    Megam::Organizations
                when MEGAM_ORGANIZATIONSCOLLECTION
                    Megam::OrganizationsCollection
                when MEGAM_DOMAIN
                    Megam::Domains
                when MEGAM_DOMAINCOLLECTION
                    Megam::DomainsCollection
                when MEGAM_SENSORS
                    Megam::Sensors
                when MEGAM_SENSORSCOLLECTION
                    Megam::SensorsCollection
                  when MEGAM_SNAPSHOTS
                      Megam::Snapshots
                  when MEGAM_SNAPSHOTSCOLLECTION
                      Megam::SnapshotsCollection
                when MEGAM_BALANCES
                    Megam::Balances
                when MEGAM_BALANCESCOLLECTION
                    Megam::BalancesCollection
                when MEGAM_BILLEDHISTORIES
                    Megam::Billedhistories
                when MEGAM_BILLEDHISTORIESCOLLECTION
                    Megam::BilledhistoriesCollection
                  when MEGAM_BILLINGTRANSCATIONS
                      Megam::Billingtranscations
                  when MEGAM_BILLINGTRANSCATIONSCOLLECTION
                      Megam::BillingtranscationsCollection
                when MEGAM_PROMOS
                    Megam::Promos
                else
                    fail JSON::ParserError, "Unsupported `json_class` type '#{json_class}'"
                end
            end
        end
    end
end
