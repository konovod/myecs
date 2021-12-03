module ECS
  annotation SingleFrame
  end

  annotation SingletonComponent
  end

  abstract struct Component
  end

  annotation MultipleComponents
  end

  DEFAULT_COMPONENT_POOL_SIZE   =   16
  DEFAULT_EVENT_POOL_SIZE       =   16
  DEFAULT_EVENT_TOTAL_POOL_SIZE =   16
  DEFAULT_ENTITY_POOL_SIZE      = 1024

  alias EntityID = UInt64
  NO_ENTITY = 0u64

  struct Entity
    getter id : EntityID
    getter world : World

    protected def initialize(@world, @id)
    end

    def add(comp : Component)
      @world.pool_for(comp).add_component(self, comp)
      self
    end

    def set(comp : Component)
      @world.pool_for(comp).add_or_update_component(self, comp)
      self
    end

    def has?(typ : ComponentType)
      @world.base_pool_for(typ).has_component?(self)
    end

    def remove(typ : ComponentType)
      @world.base_pool_for(typ).remove_component(self)
      self
    end

    def remove_if_present(typ : ComponentType)
      @world.base_pool_for(typ).try_remove_component(self)
      self
    end

    def replace(typ : ComponentType, comp : Component)
      remove(typ)
      add(comp)
    end

    def inspect(io)
      io << "Entity{" << id << "}["
      @world.pools.each { |pool| io << pool.name << "," if pool.has_component?(self) && !pool.is_singleton }
      io << "]"
    end

    def update(comp : Component)
      @world.pool_for(comp).update_component(self, comp)
    end

    def destroy
      @world.pools.each do |pool|
        pool.try_remove_component(self)
      end
    end

    macro finished
      {% for obj, index in Component.all_subclasses %} 
      {% obj_name = obj.id.split("::").last.id %}
      def get{{obj_name}}
      @world.pools[{{index}}].as(Pool({{obj}})).get_component?(self) || raise "{{obj}} not present on entity #{self}"
      end
  
      def get{{obj_name}}?
        @world.pools[{{index}}].as(Pool({{obj}})).get_component?(self)
      end

      def get{{obj_name}}_ptr
        @world.pools[{{index}}].as(Pool({{obj}})).get_component_ptr(self)
      end
      {% end %}
    end
  end

  alias ComponentType = Component.class

  abstract class BasePool
    abstract def has_component?(entity : Entity) : Bool
    abstract def remove_component(entity : Entity)
    abstract def try_remove_component(entity : Entity)
    abstract def each_entity(& : Entity ->)
    abstract def clear
    abstract def total_count : Int32
  end

  class Pool(T) < BasePool
    @size : Int32
    @used : Int32 = 0
    @raw : Slice(T)
    @corresponding : Slice(EntityID)
    @sparse = Hash(EntityID, Int32).new
    @unsafe_iterating = 0

    @cache_entity : EntityID = NO_ENTITY
    @cache_index : Int32 = -1

    def initialize(@world : World)
      @size = DEFAULT_COMPONENT_POOL_SIZE
      {% if T.annotation(ECS::SingleFrame) %}
        @size = DEFAULT_EVENT_POOL_SIZE
      {% end %}
      {% if T.annotation(ECS::SingletonComponent) %}
        @size = 1
      {% end %}
      @raw = Pointer(T).malloc(@size).to_slice(@size)
      @corresponding = Pointer(EntityID).malloc(@size).to_slice(@size)
    end

    def name
      T.to_s
    end

    def is_singleton
      {% if T.annotation(ECS::SingletonComponent) %}
        true
      {% else %}
        false
      {% end %}
    end

    private def get_free_index : Int32
      @used += 1
      grow if @used >= @size
      @used - 1
    end

    private def release_index(index)
      unless index == @used - 1
        @raw[index] = @raw[@used - 1]
        fix_entity = @corresponding[@used - 1]
        @sparse[fix_entity] = index
        @corresponding[index] = fix_entity
      end
      @used -= 1
    end

    def total_count : Int32
      @used
    end

    private def grow
      old_size = @size
      @size = @size * 2
      @raw = @raw.to_unsafe.realloc(@size).to_slice(@size)
      @corresponding = @corresponding.to_unsafe.realloc(@size).to_slice(@size)
    end

    def has_component?(entity) : Bool
      {% if T.annotation(ECS::SingletonComponent) %}
        @used > 0
      {% else %}
        return @cache_index >= 0 if entity.id == @cache_entity
        @sparse.has_key? entity.id
      {% end %}
    end

    def remove_component(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        raise "can't remove singleton #{self.class}" if @used == 0
        @used = 0
      {% else %}
        raise "can't remove component #{self.class} from #{entity}" unless has_component?(entity)
        remove_component_without_check(entity)
      {% end %}
    end

    def try_remove_component(entity)
      return unless has_component?(entity)
      remove_component_without_check(entity)
    end

    def remove_component_without_check(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
      {% elsif T.annotation(ECS::MultipleComponents) %}
        # raise "removing multiple components is not supported"
        @cache_entity = NO_ENTITY # because many entites are affected
        @sparse.delete entity.id
        # we just iterate over all array
        # TODO - faster method
        (@used - 1).downto(0) do |i|
          if @corresponding[i] == entity.id
            release_index i
          end
        end
      {% else %}
        item = entity_to_id entity.id
        @cache_entity = NO_ENTITY # because at least two entites are affected
        @sparse.delete entity.id
        release_index item
      {% end %}
    end

    def each_entity(& : Entity ->)
      {% if !T.annotation(ECS::SingletonComponent) %}
        first = 0
        last = @used
        (first...last).each do |i|
          ent = @corresponding[i]
          @cache_index = i
          @cache_entity = ent
          yield(Entity.new(@world, ent))
        end
      {% end %}
    end

    def clear
      {% if T.annotation(ECS::SingletonComponent) %}
        @used = 0
      {% else %}
        @sparse.clear
        @used = 0
        @cache_index = -1
      {% end %}
    end

    def pointer
      @raw
    end

    def add_component_without_check(entity : Entity, item)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer[0] = item.as(Component).as(T)
        @used = 1
      {% else %}
        fresh = get_free_index
        pointer[fresh] = item.as(Component).as(T)
        @sparse[entity.id] = fresh
        @cache_entity = entity.id
        @cache_index = fresh
        @corresponding[fresh] = entity.id
      {% end %}
    end

    def entity_to_id(ent : EntityID) : Int32
      return @cache_index if @cache_entity == ent
      @sparse[ent]
    end

    def update_component(entity, comp)
      {% if T.annotation(ECS::SingletonComponent) %}
        @used = 1
        pointer[0] = comp.as(Component).as(T)
      {% else %}
        pointer[entity_to_id(entity.id)] = comp.as(Component).as(T)
      {% end %}
    end

    def add_component(entity, comp)
      {% if T.annotation(ECS::SingletonComponent) %}
        add_or_update_component(entity, comp)
      {% else %}
        {% if !T.annotation(ECS::MultipleComponents) %}
          raise "#{T} already added to #{entity}" if has_component?(entity)
        {% end %}
        add_component_without_check(entity, comp)
      {% end %}
    end

    def add_or_update_component(entity, comp)
      {% if T.annotation(ECS::SingletonComponent) %}
        @used = 1
        pointer[0] = comp.as(Component).as(T)
      {% else %}
        if has_component?(entity)
          update_component(entity, comp)
        else
          add_component_without_check(entity, comp)
        end
      {% end %}
    end

    def get_component_ptr(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer.to_unsafe
      {% else %}
        (pointer + entity_to_id entity.id).to_unsafe
      {% end %}
    end

    def get_component?(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        return nil if @used == 0
        pointer[0]
      {% else %}
        return nil unless has_component?(entity)
        pointer[entity_to_id entity.id]
      {% end %}
    end
  end

  class World
    protected getter ent_id = EntityID.new(1)
    getter pools = Array(BasePool).new({{Component.all_subclasses.size}})

    @@comp_can_be_multiple = Set(ComponentType).new

    property cur_systems : Systems? # TODO - TLS
    delegate of, all_of, any_of, exclude, to: new_filter

    def initialize
      init_pools
    end

    def can_be_multiple?(typ : ComponentType)
      @@comp_can_be_multiple.includes? typ
    end

    def inspect(io)
      io << "World{max_ent=" << ent_id << "}"
    end

    def new_entity
      Entity.new(self, @ent_id).tap { @ent_id += 1 }
    end

    def new_filter
      Filter.new(self)
    end

    def delete_all
      @pools.each &.clear
    end

    @processed = Set(EntityID).new(DEFAULT_ENTITY_POOL_SIZE)

    def each_entity(& : Entity ->)
      return if pools.size == 0
      @pools.each do |pool|
        pool.each_entity do |ent|
          next if @processed.includes? ent.id
          yield(ent)
          @processed.add(ent.id)
        end
      end
      @processed.clear
    end

    def component_exists?(typ)
      base_pool_for(typ).total_count > 0
    end

    macro finished
      def init_pools
        {% for obj, index in Component.all_subclasses %} 
          @pools << Pool({{obj}}).new(self) 
          {% if obj.annotation(ECS::MultipleComponents) %}
            @@comp_can_be_multiple.add {{obj}}
          {% end %}
        {% end %}
      end

      {% for obj, index in Component.all_subclasses %} 
        def pool_for(component : {{obj}}) : Pool({{obj}})
          @pools[{{index}}].as(Pool({{obj}}))
        end
      {% end %}

      def base_pool_for(typ : ComponentType)
          {% for obj, index in Component.all_subclasses %} 
            return @pools[{{index}}] if typ == {{obj}}
          {% end %}
            raise "unregistered component type: #{typ}"
      end

    end
  end

  class Filter
    @all_of = [] of ComponentType
    @any_of = [] of Array(ComponentType)
    @exclude = [] of ComponentType
    @callbacks = [] of Proc(Entity, Bool)
    @all_multiple_component : ComponentType?
    @any_multiple_component_index : Int32?

    def initialize(@world : World)
    end

    def all_of(list)
      multiple = list.find { |typ| @world.can_be_multiple?(typ) }
      if multiple
        if list.count { |typ| @world.can_be_multiple?(typ) } > 1
          raise "iterating over several MultipleComponents isn't supported: #{list}"
        elsif old = @all_multiple_component
          raise "iterating over several MultipleComponents isn't supported: #{old} and #{multiple}"
        elsif old = @any_multiple_component_index
          raise "iterating over several MultipleComponents isn't supported: #{@any_of[old]} and #{multiple}"
        else
          @all_multiple_component = multiple
        end
      end
      @all_of.concat(list)
      self
    end

    def exclude(item : ComponentType)
      @exclude << item
      self
    end

    def exclude(list)
      @exclude.concat(list)
      self
    end

    def of(item : ComponentType)
      if @world.can_be_multiple?(item)
        if old = @all_multiple_component
          raise "iterating over several MultipleComponents isn't supported: #{old} and #{item}"
        elsif old = @any_multiple_component_index
          raise "iterating over several MultipleComponents isn't supported: #{@any_of[old]} and #{item}"
        else
          @all_multiple_component = item
        end
      end
      @all_of << item
      self
    end

    def any_of(list)
      if list.size == 1
        return of(list.first)
      end
      raise "any_of list can't be empty" if list.size == 0

      multiple = list.find { |typ| @world.can_be_multiple?(typ) }
      if multiple
        if list.count { |typ| @world.can_be_multiple?(typ) } > 1
          raise "iterating over several MultipleComponents isn't supported: #{list}"
        elsif old = @all_multiple_component
          raise "iterating over several MultipleComponents isn't supported: #{old} and #{multiple}"
        elsif old = @any_multiple_component_index
          raise "iterating over several MultipleComponents isn't supported: #{@any_of[old]} and #{multiple}"
        else
          @any_multiple_component_index = @any_of.size
          list = list.dup
          list.delete(multiple)
          list.unshift multiple
        end
      end

      @any_of << list.map { |x| x.as(ComponentType) }
      self
    end

    def select(&block : Entity -> Bool)
      @callbacks << block
      self
    end

    private def pass_any_of_filter(entity) : Bool
      @any_of.each do |list|
        return false if list.all? { |typ| !entity.has?(typ) }
      end
      true
    end

    private def pass_all_of_filter(entity) : Bool
      return false if @all_of.any? { |typ| !entity.has?(typ) }
      true
    end

    private def pass_exclude_and_select_filter(entity) : Bool
      return false if @exclude.any? { |typ| entity.has?(typ) }
      return false if @callbacks.any? { |cb| !cb.call(entity) }
      true
    end

    def satisfy(entity : Entity)
      return pass_all_of_filter(entity) && pass_any_of_filter(entity) && pass_exclude_and_select_filter(entity)
    end

    private def already_processed_in_list(entity, list, index)
      index.times do |i|
        typ = list[i]
        return true if entity.has?(typ)
      end
      false
    end

    def find_entity?
      each_entity do |ent|
        return ent
      end
      nil
    end

    def count_entities?
      n = 0
      each_entity do
        n += 1
      end
      n
    end

    private def iterate_over_type(typ, & : Entity ->)
      @world.base_pool_for(typ).each_entity do |entity|
        next unless satisfy(entity)
        yield(entity)
      end
    end

    private def iterate_over_list(list, & : Entity ->)
      list.each_with_index do |typ, index|
        @world.base_pool_for(typ).each_entity do |entity|
          next if already_processed_in_list(entity, list, index)
          next unless satisfy(entity)
          yield(entity)
        end
      end
    end

    private def iterate_over_world(& : Entity ->)
      @world.each_entity do |entity|
        next unless satisfy(entity)
        yield(entity)
      end
    end

    def each_entity(& : Entity ->)
      smallest_all_count = 0
      smallest_any_count = 0
      smallest_all = nil
      smallest_any = nil

      if all = @all_multiple_component
        smallest_all = all
        smallest_any = nil
      elsif any = @any_multiple_component_index
        smallest_all = nil
        smallest_any = @any_of[any]
      else
        if @all_of.size > 0
          # we use all_of and find shortest pool
          smallest_all = @all_of.min_by { |typ| @world.base_pool_for(typ).total_count }
          smallest_all_count = @world.base_pool_for(smallest_all).total_count
          return if smallest_all_count == 0
        end
        if @any_of.size > 0
          smallest_any = @any_of.min_by do |list|
            list.sum(0) { |typ| @world.base_pool_for(typ).total_count }
          end
          smallest_any_count = smallest_any.sum(0) { |typ| @world.base_pool_for(typ).total_count }
          return if smallest_any_count == 0
        end
      end

      if smallest_all && (!smallest_any || smallest_all_count <= smallest_any_count)
        # iterate by smallest_all
        iterate_over_type(smallest_all) do |entity|
          yield(entity)
        end
      elsif smallest_any
        # iterate by smallest_any
        iterate_over_list(smallest_any) do |entity|
          yield(entity)
        end
      else
        # iterate everything
        iterate_over_world do |entity|
          yield(entity)
        end
      end
    end
  end

  class System
    property active = true

    def initialize(@world : ECS::World)
    end

    def init
    end

    def execute
    end

    def do_execute
      if @active
        # puts "#{self.class.name} begin"
        execute
        # puts "#{self.class.name} end"
      end
    end

    def teardown
    end

    def filter(world : World) : Filter?
      nil
    end

    def process(entity : Entity)
    end
  end

  class RemoveAllOf(T) < System
    def execute
      @world.base_pool_for(T).clear
    end
  end

  class Systems < System
    getter children = [] of System
    @filters = [] of Filter?
    @cur_child : System?

    def initialize(@world : World)
      @started = false
    end

    def add(sys : System)
      children << sys
      sys.init if @started
      self
    end

    def add(sys : System.class)
      add(sys.new(@world))
    end

    def init
      raise "#{self.class} already initialized" if @started
      @children.each &.init
      @filters = @children.map { |x| x.filter(@world).as(Filter | Nil) }
      @started = true
    end

    def execute
      raise "#{@children.map(&.class)} wasn't initialized" unless @started
      @world.cur_systems = self
      @children.zip(@filters) do |sys, filter|
        @cur_child = sys
        if filter && sys.active
          filter.each_entity { |ent| sys.process(ent) }
        end
        sys.do_execute
      end
      @world.cur_systems = nil
    end

    def teardown
      raise "#{self.class} not initialized" unless @started
      @children.each &.teardown
      @started = false
    end
  end
end
