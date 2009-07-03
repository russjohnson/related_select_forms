#--
# Copyright (C) 2007 Dimitrij Denissenko
# Please read LICENSE document for more information.
#++


# This plugin adds a new helper to the great RubyOnRails framework that 
# allows to generate multiple, dependent HTML select tags. It handles 
# the relations with simple JavaScript (requires prototype.js library), 
# so you do not need to code any AJAX callbacks (can be handy when you
# only deal with a small amount of data). This plugin works also 
# well with RJS templates and supports recursive pre-selection of the
# related select tags.
module ActionView::Helpers::RelatedSelectFormHelper

  # Return a dependent select tag with options related to the 
  # parent_select_tag selection for the given object and method using 
  # options_from_collection_for_select to generate the list of option tags.
  #
  #     related_collection_select(
  #         object, method, parent_select_tag, collection, 
  #         value_method, text_method, reference_method, 
  #         options = {}, html_options = {})
  # 
  # === Arguments:
  # 
  # * 'object', 'method', 'collection', 'value_method', 'text_method', 
  #   'options' & 'html_options' are used exactly the same way as in
  #   the standard collection_select helper method. 
  # * 'parent_select_tag' specifies, as the name says, the parent 
  #   select tag; argument can be passed as an array 
  #   [:parent_object, :method] or directly as string referencing the 
  #   tag id (e.g. "parent_object_method")
  # * Parameter 'reference_method' specifies the method that is used to get
  #   a reference to parent selection.
  #   
  # Additionally the 'options' argument can include a ':selected' attribute,
  # that will override the default pre-selection behaviour (which uses to call 
  # '@object.method' to determine the to be selected option).
  # 
  # You can also pass an :include_blank attribute consisting of true, false (default), a string, or a 
  # two-element array, just like the standard Rails select form helper. If you do not set this attribute, 
  # the related select will default to the first option.
  # 
  # === Example:
  # 
  # <b>Models</b>
  # 
  #   class Metro < ActiveRecord::Base
  #   ÊÊ has_many :areas
  #   end
  #   
  #   class Area < ActiveRecord::Base
  #   ÊÊ belongs_to :metro
  #   ÊÊ has_many :neighborhoods
  #   end
  #   
  #   class Neighborhood < ActiveRecord::Base
  #   ÊÊ belongs_to :area
  #   end
  # 
  #   Just looking at the models it should be plain to see how the selects should be related. You must 
  #   first select a Metro, then that will populate the Areas. Once you select the area, that will 
  #   populate the Neighborhoods.
  # 
  # <b>View</b>
  # 
  #   Normally this would take a lot of handwritten Javascript to accomplish. And I know there are 
  #   probably some super simple jQuery plugins for this thing, but this application is using the standard 
  #   Prototype/Scriptaculous combo that ships with Rails.
  # 
  #   So here is the how simple the form fields are using the plugin:
  # 
  #     <%- form_for(@sales_contact) do |f| -%>
  # 
  #       <%= f.label :metro_id, '', :class => 'title' %>
  #       <%= f.collection_select :metro_id, Metro.find(:all, :order => "name"), :id, :name, 
  #       :include_blank => 'Select a Metro %>
  #   
  #       <%= f.label :area_id, '', :class => 'title' %>
  #       <%= related_collection_select(:sales_contact, :area_id, [:sales_contact_metro, :id], 
  #       Area.find(:all,:order => "area" ), :id, :area, :metro_id, :include_blank => 'Select an Area') %>
  #   
  #       <%= f.label :neighborhood_id, '', :class => "title" %>
  #       <%= related_collection_select(:sales_contact, :neighborhood_id, [:sales_contact_area, :id], 
  #       Neighborhood.find(:all,:order => "title"), :id, :title, :area_id, :include_blank => 'Select a 
  #       Neighborhood') %>
  # 
  #       ...
  #     
  #   Notice the first select is a standard collection_select, then for each related field we make calls 
  #   to the plugin. The method signature is very similar to the standard collection_select with the 
  #   addition of a couple of parent-related arguments.
  # 
  def related_collection_select(object, method, parent_element, collection, value_method, text_method, reference_method, options = {}, html_options = {})                  
    relations = collection.inject({}) do |result, record|
      reference_value = record.send(reference_method).to_s
      record_value    = record.send(value_method).to_s
      
      result[reference_value] ||= ActiveSupport::OrderedOptions.new
      result[reference_value][record_value] ||= []
      result[reference_value][record_value] << record.send(text_method)
      result
    end
    parent_tag_id = parent_element.is_a?(Array) ? parent_element.collect{|t| t.to_s}.join('_') : parent_element.to_s

    ActionView::Helpers::InstanceTag.new(object, method, self, options.delete(:object)).
      to_related_collection_select_tag(parent_tag_id, relations, options, html_options)
  end

end    
ActionView::Base.send :include, ActionView::Helpers::RelatedSelectFormHelper



class ActionView::Helpers::InstanceTag #:nodoc:  
  include ActionView::Helpers::JavaScriptHelper

  def to_related_collection_select_tag(parent_tag_id, relations, options = {}, html_options = {})  #:nodoc: 
    html_options.stringify_keys!
    add_default_name_and_id(html_options)
    store_collection_relations_for_current_request(parent_tag_id, relations)   

    selected_value = options.has_key?(:selected) ? options[:selected] : value(object)    

    (related_select_cache.size == 1 ? javascript_tag(javascript_code_for_related_select_extension) : '') +
      content_tag("select", '', html_options) +
      javascript_tag(javascript_code_for_relation_hookup(parent_tag_id, relations, selected_value, options)) + 
      javascript_tag(javascript_code_for_preselection(selected_value))
  end  

  private
    
    def store_collection_relations_for_current_request(parent_tag_id, relations)
      inverted_relation_values = relations.inject({}) do |result, (parent_value, relation)|
        relation.keys.each { |child_value| result[child_value.to_s] ||= parent_value.to_s }
        result
      end
      related_select_cache[tag_id] ||= {:parent => parent_tag_id, :relations => inverted_relation_values}
    end      
    
    def related_select_cache     
      unless @template_object.respond_to?(:related_select_cache)
        @template_object.class.send(:attr_accessor, :related_select_cache)
      end
      @template_object.related_select_cache ||= {}      
    end

    def javascript_code_for_preselection(selected_value, element_id = tag_id)
      return "$('#{element_id}').refresh();" if selected_value.blank?

      code = ["$('#{element_id}').select('#{selected_value}');"]
      while relations = related_select_cache[element_id]
        element_id = relations[:parent]
        selected_value = relations[:relations][selected_value.to_s]
        code << "$('#{element_id}').select('#{selected_value}');"
      end
      '      ' + code.reverse.join(' ')
    end

    def javascript_code_for_relation_hookup(parent_tag_id, relations, selected_value, options = {})
      javascript_relations = javascript_code_for_relation_hash(relations, selected_value, options)

      "
      if ($('#{parent_tag_id}').extended_html_select_object != true) Object.extend($('#{parent_tag_id}'), HTMLRelatedSelectStruct); 
      if ($('#{tag_id}').extended_html_select_object != true) Object.extend($('#{tag_id}'), HTMLRelatedSelectStruct); 
      $('#{parent_tag_id}').child_add($('#{tag_id}')); $('#{tag_id}').select_parent = $('#{parent_tag_id}');
      $('#{tag_id}').relation_hash = {
        #{javascript_relations}
      };
      "
    end

    def javascript_code_for_related_select_extension
      "
      var HTMLRelatedSelectStruct = {
        select_children: undefined, 
        select_parent: undefined,
        relation_hash: undefined,
        extended_html_select_object: true,
        select: function(value) {
          for (i=0; i < this.options.length; i++) { 
            if (this.options[i].value == value) this.selectedIndex = i; 
          }
          this.refresh_children();
        },
        child_add: function(child) {
          if (this.select_children == undefined) this.select_children = [];
          this.select_children.push(child);
        },            
        refresh_children: function() {
          if (this.select_children != undefined) {
            this.select_children.each( function(child){ child.refresh(); } );
          }
        },
        refresh: function() {
          this.options.length = 0;
          if (this.select_parent != undefined && this.relation_hash != undefined && this.select_parent.selectedIndex > -1) {
            opts = this.relation_hash[this.select_parent.options[this.select_parent.selectedIndex].value];
            if (opts != undefined) {
              for (i=0; i<opts.length; i++) this.options[i] = opts[i];
              this.refresh_children();
            }
          }
        },
        onchange: function() { this.refresh_children(); }            
      };        
      "
    end      

    def javascript_code_for_relation_hash(relations, value, options)
      relations.collect do |(reference_value, records)|           
        choices = []
        case options[:include_blank].class.name
          when "FalseClass"
            _blank = nil
          when "String"
            _blank = [options[:include_blank], '']
          when "Array"
            _blank = options[:include_blank]
          else
            _blank = ['','']
        end
        choices << "new Option('#{_blank[0]}', '#{_blank[0]}')" unless _blank.nil?
        if value.blank? && options[:prompt]
          choices << "new Option('#{options[:prompt].kind_of?(String) ? options[:prompt] : 'Please select'}', '')"
        end

        choices += records.collect do |(value, text)| 
          "new Option('#{escape_javascript(text.to_s)}', '#{escape_javascript(value.to_s)}')" 
        end

        "#{reference_value}: [#{choices.join(', ')}]"
      end.join(",\n        ")
    end      
                  
end







