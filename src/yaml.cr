require "yaml"

module ECS
  abstract struct YAMLComponent < ECS::Component
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
          "type".to_yaml(yaml)
          self.class.name.to_yaml(yaml)
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

  class YAMLSerializer
    @@entities = Hash(String, Entity).new

    def self.prepare(world)
      @@entities = Hash(String, Entity).new { |h, x| ent = world.new_entity; h[x] = ent; ent }
    end

    def self.storage
      @@entities
    end

    def self.reset
      @@entities = Hash(String, Entity).new
    end
  end

  struct Entity
    def self.new(ctx : YAML::ParseContext, node : YAML::Nodes::Node)
      name = String.new(ctx, node)
      YAMLSerializer.storage[name]
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

    def read_yaml(io)
      stubs = Hash(String, Array(YAMLComponent)).from_yaml(io)
      stubs.each do |k, v|
        ent = YAMLSerializer.storage[k]
        v.each do |comp|
          ent.add(comp)
        end
      end
    end

    def from_yaml_dir(dir)
      YAMLSerializer.prepare(self)
      Dir.glob(dir) do |filename|
        File.open(filename) do |file|
          read_yaml(file)
        end
      end
      YAMLSerializer.reset
    end
  end
end
