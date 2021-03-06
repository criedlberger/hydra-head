module Hydra
  module AdminPolicyBehavior
    extend ActiveSupport::Concern

    included do
      has_and_belongs_to_many :default_permissions, predicate: Hydra::ACL.defaultPermissions, class_name: 'Hydra::AccessControls::Permission'
      belongs_to :default_embargo, predicate: Hydra::ACL.hasEmbargo, class_name: 'Hydra::AccessControls::Embargo'
    end

    def to_solr(solr_doc=Hash.new)
      f = merged_policies
      super.tap do |doc|
        ['discover'.freeze, 'read'.freeze, 'edit'.freeze].each do |access|
          doc[Hydra.config.permissions.inheritable[access.to_sym][:group]] = f[access]['group'.freeze] if f[access]
          doc[Hydra.config.permissions.inheritable[access.to_sym][:individual]] = f[access]['person'.freeze] if f[access]
        end
        if default_embargo
          key = Hydra.config.permissions.inheritable.embargo.release_date.sub(/_[^_]+$/, '') #Strip off the suffix
          ::Solrizer.insert_field(doc, key, default_embargo.embargo_release_date, :stored_sortable)
        end
      end
    end

    def merged_policies
      default_permissions.each_with_object({}) do |policy, h|
        args = policy.to_hash
        h[args[:access]] ||= {}
        h[args[:access]][args[:type]] ||= []
        h[args[:access]][args[:type]] << args[:name]
      end
    end


    ## Updates those permissions that are provided to it. Does not replace any permissions unless they are provided
    # @example
    #  obj.default_permissions= [{:name=>"group1", :access=>"discover", :type=>'group'},
    #  {:name=>"group2", :access=>"discover", :type=>'group'}]
    def default_permissions=(params)
      perm_hash = {'person' => defaultRights.users, 'group'=> defaultRights.groups}
      params.each do |row|
        if row[:type] == 'user' || row[:type] == 'person'
          perm_hash['person'][row[:name]] = row[:access]
        elsif row[:type] == 'group'
          perm_hash['group'][row[:name]] = row[:access]
        else
          raise ArgumentError, "Permission type must be 'user', 'person' (alias for 'user'), or 'group'"
        end
      end
      defaultRights.update_permissions(perm_hash)
    end

    ## Returns a list with all the permissions on the object.
    # @example
    #  [{:name=>"group1", :access=>"discover", :type=>'group'},
    #  {:name=>"group2", :access=>"discover", :type=>'group'},
    #  {:name=>"user2", :access=>"read", :type=>'user'},
    #  {:name=>"user1", :access=>"edit", :type=>'user'},
    #  {:name=>"user3", :access=>"read", :type=>'user'}]
    def default_permissions
      (defaultRights.groups.map {|x| {:type=>'group', :access=>x[1], :name=>x[0] }} + 
       defaultRights.users.map {|x| {:type=>'user', :access=>x[1], :name=>x[0]}})
    end

  end
end
