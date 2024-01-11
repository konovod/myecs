require "yaml"

module ECS
  # hack to add entities table to the YAML parser
  private record FakeNode, anchor : String

  abstract struct YAMLComponent < Component
    include YAML::Serializable

    def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
      {% begin %}
        ctx.read_alias(node, \{{@type}}) do |obj|
          return obj
        end
        unless node.is_a?(YAML::Nodes::Mapping)
          node.raise "expected YAML mapping, not #{node.class}"
        end

        node.each do |key, value|
          next unless key.is_a?(YAML::Nodes::Scalar) && value.is_a?(YAML::Nodes::Scalar)
          next unless key.value == "type"

          discriminator_value = value.value
          case discriminator_value
          {% for obj in YAMLComponent.all_subclasses %} 
            when {{obj.id.stringify}}
            result = {{obj.id}}.new(ctx, node)
            result.after_initialize
            return result
          {% end %}
          else
            node.raise "Unknown 'type' discriminator value: #{discriminator_value.inspect}"
          end
        end
        node.raise "Missing YAML discriminator field 'type'"
      {% end %}
    end

    # this is a hack - it copies substancial part of logic from Crystal stdlib just for one thing - automatically serialize `type` field
    def to_yaml(yaml : ::YAML::Nodes::Builder)
      {% begin %}
        {% options = @type.annotation(::YAML::Serializable::Options) %}
        {% emit_nulls = options && options[:emit_nulls] %}

        {% properties = {} of Nil => Nil %}
        {% for ivar in @type.instance_vars %}
          {% ann = ivar.annotation(::YAML::Field) %}
          {% unless ann && (ann[:ignore] || ann[:ignore_serialize] == true) %}
            {%
              properties[ivar.id] = {
                key:              ((ann && ann[:key]) || ivar).id.stringify,
                converter:        ann && ann[:converter],
                emit_null:        (ann && (ann[:emit_null] != nil) ? ann[:emit_null] : emit_nulls),
                ignore_serialize: ann && ann[:ignore_serialize],
              }
            %}
          {% end %}
        {% end %}

        yaml.mapping(reference: self) do
          # These are two strings that was added
          # ------------
          "type".to_yaml(yaml)
          self.class.name.to_yaml(yaml)
          # ------------
          {% for name, value in properties %}
            _{{name}} = @{{name}}

            {% if value[:ignore_serialize] %}
              unless {{value[:ignore_serialize]}}
            {% end %}

              {% unless value[:emit_null] %}
                unless _{{name}}.nil?
              {% end %}

                {{value[:key]}}.to_yaml(yaml)

                {% if value[:converter] %}
                  if _{{name}}
                    {{ value[:converter] }}.to_yaml(_{{name}}, yaml)
                  else
                    nil.to_yaml(yaml)
                  end
                {% else %}
                  _{{name}}.to_yaml(yaml)
                {% end %}

              {% unless value[:emit_null] %}
                end
              {% end %}
            {% if value[:ignore_serialize] %}
              end
            {% end %}
          {% end %}
          on_to_yaml(yaml)
        end
      {% end %}
    end

    protected def on_unknown_yaml_attribute(ctx, key, key_node, value_node)
      key_node.raise "Unknown yaml attribute: #{key}" unless key == "type"
    end

    def self.new
    end
  end

  class EntitiesHash
    @entities = Hash(String, Entity).new

    def initialize(world)
      @entities = Hash(String, Entity).new { |h, x| ent = world.new_entity; h[x] = ent; ent }
    end

    def storage
      @entities
    end

    def reset
      @entities = Hash(String, Entity).new
    end
  end

  struct Entity
    def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
      name = String.new(ctx, node)
      # storage = ctx.read_alias(FakeNode.new("_ecs_storage"), EntitiesHash)
      object_id, _ = ctx.@anchors["_ecs_storage"]
      storage = Pointer(Void).new(object_id).as(EntitiesHash)
      storage.storage[name]
    end

    def to_yaml_id(yaml : YAML::Nodes::Builder) : Nil
      "Entity#{self.id}".to_yaml(yaml)
    end

    def to_yaml(yaml : YAML::Nodes::Builder) : Nil
      to_yaml_id(yaml)
    end

    def to_yaml_comps(yaml : YAML::Nodes::Builder) : Nil
      {% begin %}
      yaml.sequence(reference: self) do
        {% for obj in YAMLComponent.all_subclasses %} 
          if x = self.get{{obj.id}}?
            x.to_yaml(yaml)
          end
        {% end %}
      end
    {% end %}
    end
  end

  class World
    def to_yaml(yaml : YAML::Nodes::Builder) : Nil
      yaml.mapping(reference: self) do
        self.each_entity do |ent|
          ent.to_yaml_id(yaml)
          ent.to_yaml_comps(yaml)
        end
      end
    end

    def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
      world = self.new
      names = EntitiesHash.new(world)
      ctx.record_anchor(FakeNode.new("_ecs_storage"), names)
      stubs = Hash(String, Array(YAMLComponent)).new(ctx, node)
      stubs.each do |k, v|
        ent = names.storage[k]
        v.each do |comp|
          ent.add(comp)
        end
      end
      world
    end

    def add_yaml(io_or_string)
      YAMLReader.new(self).read(io_or_string)
    end

    def add_yaml(&)
      yield(YAMLReader.new(self))
      self
    end

    def self.from_yaml(&)
      self.new.add_yaml { |yaml| yield(yaml) }
    end
  end

  struct YAMLReader
    @names : EntitiesHash

    def initialize(owner)
      @names = EntitiesHash.new(owner)
    end

    def read(io_or_string)
      ctx = YAML::ParseContext.new
      node = YAML::Nodes.parse(io_or_string).nodes.first
      ctx.record_anchor(FakeNode.new("_ecs_storage"), @names)
      stubs = Hash(String, Array(YAMLComponent)).new(ctx, node)
      stubs.each do |k, v|
        ent = @names.storage[k]
        v.each do |comp|
          ent.add(comp)
        end
      end
      self
    end
  end
end
