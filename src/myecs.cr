module ECS
  # Component - container for user data without / with small logic inside.
  # All components should be inherited from `ECS::Component`
  abstract struct Component
  end

  # Represents component that should exist for one frame and be deleted after.
  annotation SingleFrame
  end

  # Represents component that doesn't belong to specific entity. Instead, it can be acquired from every entity.
  annotation SingletonComponent
  end

  # Represents component that can be present on any entity more than once.
  annotation MultipleComponents
  end

  private DEFAULT_COMPONENT_POOL_SIZE   =   16
  private DEFAULT_EVENT_POOL_SIZE       =   16
  private DEFAULT_EVENT_TOTAL_POOL_SIZE =   16
  private DEFAULT_ENTITY_POOL_SIZE      = 1024

  # Entity Identifier
  alias EntityID = UInt32

  # Identifier that doesn't match any entity
  NO_ENTITY = 0u32

  # Сontainer for components. Consists from UInt64 and pointer to `World`
  struct Entity
    # ID of entity
    getter id : EntityID
    # World that contains entity
    getter world : World

    protected def initialize(@world, @id)
    end

    # Adds component to the entity.
    # Will raise if component already exists (and doesn't have `MultipleComponents` annotation)
    def add(comp : Component)
      @world.pool_for(comp).add_component(self, comp)
      self
    end

    # Adds component to the entity or update existing component of same type
    def set(comp : Component)
      @world.pool_for(comp).add_or_update_component(self, comp)
      self
    end

    # Returns true if component of type `typ` exists on the entity
    def has?(typ : ComponentType)
      @world.base_pool_for(typ).has_component?(self)
    end

    # Removes component of type `typ` from the entity. Will raise if component isn't present on entity
    def remove(typ : ComponentType)
      @world.base_pool_for(typ).remove_component(self)
      self
    end

    # Removes component of type `typ` from the entity if it exists. Otherwise, do nothing
    def remove_if_present(typ : ComponentType)
      @world.base_pool_for(typ).try_remove_component(self)
      self
    end

    # Deletes component of type `typ` and add component `comp` to the entity
    def replace(typ : ComponentType, comp : Component)
      add(comp)
      remove(typ)
    end

    def inspect(io)
      io << "Entity{" << id << "}["
      @world.pools.each { |pool| io << pool.name << "," if pool.has_component?(self) && !pool.is_singleton }
      io << "]"
    end

    # Update existing component of same type on the entity. Will raise if component of this type isn't present.
    def update(comp : Component)
      @world.pool_for(comp).update_component(self, comp)
    end

    # Destroys entity removing all components from it.
    # For now, IDs are not reused, so it is safe to hold entity even when it was destroyed
    # and add components later
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

  # type that represents type of any component
  alias ComponentType = Component.class

  private abstract class BasePool
    abstract def has_component?(entity : Entity) : Bool
    abstract def remove_component(entity : Entity)
    abstract def try_remove_component(entity : Entity)
    abstract def each_entity(& : Entity ->)
    abstract def clear
    abstract def total_count : Int32
  end

  private class Pool(T) < BasePool
    @size : Int32
    @used : Int32 = 0
    @raw : Slice(T)
    @corresponding : Slice(EntityID)
    @sparse : Slice(Int32)
    @unsafe_iterating = 0

    @cache_entity : EntityID = NO_ENTITY
    @cache_index : Int32 = -1
    property deleter_registered = false

    def initialize(@world : World)
      @size = DEFAULT_COMPONENT_POOL_SIZE
      {% if T.annotation(ECS::SingleFrame) %}
        @size = DEFAULT_EVENT_POOL_SIZE
      {% end %}
      {% if T.annotation(ECS::SingletonComponent) %}
        @size = 1
      {% end %}
      @sparse = Pointer(Int32).malloc(@world.entities_count + 1).to_slice(@world.entities_count + 1)
      @sparse.fill(-1)
      @raw = Pointer(T).malloc(@size).to_slice(@size)
      @corresponding = Pointer(EntityID).malloc(@size).to_slice(@size)
    end

    protected def resize_sparse(count)
      old = @sparse.size
      @sparse = @sparse.to_unsafe.realloc(count + 1).to_slice(count + 1)
      (old..count).each do |i|
        @sparse[i] = -1
      end
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
        return true if entity.id == @cache_entity
        @sparse[entity.id] >= 0
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
        @sparse[entity.id] = -1
        # we just iterate over all array
        # TODO - faster method
        (@used - 1).downto(0) do |i|
          if @corresponding[i] == entity.id
            release_index i
          end
        end
        @world.check_gc_entity entity
      {% else %}
        item = entity_to_id entity.id
        @cache_entity = NO_ENTITY if @cache_index == item || @cache_index == @used - 1
        @sparse[entity.id] = -1
        release_index item
        @world.check_gc_entity entity
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
        @sparse.fill(-1)
        @used = 0
        @cache_entity = NO_ENTITY
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
        {% if T.annotation(ECS::SingleFrame) && (!T.annotation(ECS::SingleFrame).named_args.keys.includes?("check".id) || T.annotation(ECS::SingleFrame)[:check]) %}
          raise "#{T} is created but never deleted" unless @deleter_registered
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
          {% if T.annotation(ECS::SingleFrame) && (!T.annotation(ECS::SingleFrame).named_args.keys.includes?("check".id) || T.annotation(ECS::SingleFrame)[:check]) %}
            raise "#{T} is created but never deleted" unless @deleter_registered
          {% end %}
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

  # Root level container for all entities / components, is iterated with `ECS::Systems`
  class World
    @free_entities = LinkedList.new(DEFAULT_ENTITY_POOL_SIZE)
    protected getter pools = Array(BasePool).new({{Component.all_subclasses.size}})

    @@comp_can_be_multiple = Set(ComponentType).new

    protected def register_singleframe_deleter(typ)
      base_pool_for(typ).deleter_registered = true
    end

    protected property cur_systems : Systems? # TODO - TLS

    # Creates new `Filter` and adds a condition to it
    delegate of, all_of, any_of, exclude, to: new_filter

    # Creates empty world
    def initialize
      init_pools
    end

    protected def can_be_multiple?(typ : ComponentType)
      @@comp_can_be_multiple.includes? typ
    end

    def inspect(io)
      io << "World{entities: " << entities_count << "}"
    end

    def entities_count
      @free_entities.count
    end

    # Creates new entity in a world context.
    # Basically doesn't cost anything as it just increase entities counter.
    # Entity don't take up space without components.
    def new_entity
      if @free_entities.remaining <= 0
        @free_entities.resize(@free_entities.count*2)
        @pools.each &.resize_sparse(@free_entities.count)
      end
      Entity.new(self, EntityID.new(@free_entities.next_item + 1))
    end

    # Creates new Filter.
    # This call can be skipped:
    # Instead of `world.new_filter.of(Comp1)` you can do `world.of(Comp1)`
    def new_filter
      Filter.new(self)
    end

    # Deletes all components and entities from the world
    def delete_all
      @free_entities.clear
      @pools.each &.clear
    end

    @processed = Set(EntityID).new(DEFAULT_ENTITY_POOL_SIZE)

    # Iterates over all entities
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

    # Returns true if at least one component of type `typ` exists in a world
    def component_exists?(typ)
      base_pool_for(typ).total_count > 0
    end

    # Returns simple (stack-allocated) filter that can iterate over single component
    def query(typ)
      SimpleFilter.new(self, typ)
    end

    protected def check_gc_entity(entity)
      @pools.each do |pool|
        return if pool.has_component? entity
      end
      @free_entities.release(Int32.new(entity.id - 1))
    end

    macro finished
      private def init_pools
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

        {% if obj.annotation(ECS::SingletonComponent) %}
          {% obj_name = obj.id.split("::").last.id %}
          def get{{obj_name}}
          @pools[{{index}}].as(Pool({{obj}})).get_component?(Entity.new(self, NO_ENTITY)) || raise "{{obj}} was not created"
          end
      
          def get{{obj_name}}?
            @pools[{{index}}].as(Pool({{obj}})).get_component?(Entity.new(self, NO_ENTITY))
          end
    
          def get{{obj_name}}_ptr
            @pools[{{index}}].as(Pool({{obj}})).get_component_ptr(Entity.new(self, NO_ENTITY))
          end
        {% end %}
    
      {% end %}

      protected def base_pool_for(typ : ComponentType)
          {% for obj, index in Component.all_subclasses %} 
            return @pools[{{index}}] if typ == {{obj}}
          {% end %}
            raise "unregistered component type: #{typ}"
      end

      # Non-allocating version of `stats`. Yields pairs of component name and count of corresponding components
      # ```
      # world = init_benchmark_world(1000000)
      # world.stats do |comp_name, value| 
      #   puts "#{comp_name}: #{value}" 
      # end
      # ```
      def stats(&: String, Int32 ->)
        @pools.each do |pool|
          next if pool.total_count == 0
          yield(pool.name, pool.total_count)
        end
      end

      # Returns Hash containing count of components
      # ```
      # world = init_benchmark_world(1000000)
      # puts world.stats # prints {"Comp1" => 500000, "Comp2" => 333334, "Comp3" => 200000, "Comp4" => 142858, "Config" => 1}
      # ```
      def stats
        result = {} of String => Int32
        stats do |name, count|
          result[name] = count
        end
        result
      end
    end
  end

  module AbstractFilter
    abstract def satisfy(entity : Entity) : Bool
    abstract def each_entity(& : Entity ->)

    # Returns entity that match the filter or `nil` if there are no such entities
    def find_entity?
      each_entity do |ent|
        return ent
      end
      nil
    end

    # Returns number of entities that match the filter.
    # Note that for `MultipleComponents` single entity can be called multiple times, once for each component present on entity
    def count_entities
      n = 0
      each_entity do
        n += 1
      end
      n
    end
  end

  struct SimpleFilter
    include AbstractFilter
    @pool : BasePool

    def initialize(@world : World, @typ : ComponentType)
      @pool = @world.base_pool_for(@typ)
    end

    def satisfy(entity : Entity) : Bool
      entity.has? @typ
    end

    def count_entities
      @pool.total_count
    end

    def each_entity(& : Entity ->)
      @pool.each_entity do |entity|
        yield(entity)
      end
    end
  end

  # Allows to iterate over entities with specified conditions.
  # Created by call `world.new_filter` or just by adding any conditions to `world`.
  # Following conditions are possible:
  # - entity must have ALL listed components: `filter.all_of([Comp1, Comp2])`, `filter.of(Comp1)`
  # - entity must have AT LEAST ONE of listed components: `filter.any_of([Comp1, Comp2])`
  # - entity must have NONE of listed components: `filter.exclude([Comp1, Comp2])`, `filter.exclude(Comp1)`
  # - specified Proc must return true when called on entity: `filter.select { |ent| ent.getComp1.size > 1 }`
  # conditions can be specified in any order, multiple conditions of same type are allowed
  class Filter
    include AbstractFilter
    @all_of = [] of ComponentType
    @any_of = [] of Array(ComponentType)
    @exclude = [] of ComponentType
    @callbacks = [] of Proc(Entity, Bool)
    @all_multiple_component : ComponentType?
    @any_multiple_component_index : Int32?

    protected def initialize(@world : World)
    end

    # Adds a condition that entity must have ALL listed components.
    # Example: `filter.all_of([Comp1, Comp2])`
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

    # Adds a condition that entity must not have specified component.
    # Example: `filter.exclude(Comp1)`
    def exclude(item : ComponentType)
      @exclude << item
      self
    end

    # Adds a condition that entity must have NONE of listed components.
    # Example: `filter.exclude([Comp1, Comp2])`
    def exclude(list)
      @exclude.concat(list)
      self
    end

    # Adds a condition that entity must have specified component.
    # Example: `filter.of(Comp1)`
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

    # Adds a condition that entity must have AT LEAST ONE of specified components.
    # Example: `filter.any_of([Comp1, Comp2])`
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

    # Adds a condition that specified Proc must return true when called on entity.
    # Example: `filter.select { |ent| ent.getComp1.size > 1 }`
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

    # Returns true if entity satisfy the filter
    def satisfy(entity : Entity) : Bool
      return pass_all_of_filter(entity) && pass_any_of_filter(entity) && pass_exclude_and_select_filter(entity)
    end

    private def already_processed_in_list(entity, list, index)
      index.times do |i|
        typ = list[i]
        return true if entity.has?(typ)
      end
      false
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

    # Calls a block once for each entity that match the filter.
    # Note that for `MultipleComponents` single entity can be called multiple times, once for each component present on entity
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

  # Сontainer for logic for processing filtered entities.
  # User systems should inherit from `ECS::System`
  # and implement `init`, `execute`, `teardown`, `filter` and `process` (in any combination. Just skip methods you don't need).
  class System
    # Set `active` property to false to temporarily disable system
    property active = true

    # Constructor. Called before `init`
    def initialize(@world : ECS::World)
    end

    # Will be called once during ECS::Systems.init call
    def init
    end

    # Will be called on each ECS::Systems.execute call
    def execute
    end

    protected def do_execute
      if @active
        # puts "#{self.class.name} begin"
        execute
        # puts "#{self.class.name} end"
      end
    end

    # Will be called once during ECS::Systems.teardown call
    def teardown
    end

    # Called once during ECS::Systems.init, after #init call.
    # If this method present, it should return a filter that will be applied to a world
    # Example:
    # ```
    # def filter(world : World)
    #   world.of(Component1)
    # end
    # ```
    def filter(world : World) : Filter?
      nil
    end

    # Called during each ECS::Systems.execute call, before #execute, for each entity that match the #filter
    def process(entity : Entity)
    end
  end

  # This system deletes all components of specified type during execute.
  # This is a recommended way of deleting `SingleFrame` components.
  # Example: `systems.add(ECS::RemoveAllOf.new(@world, Component1))`
  class RemoveAllOf < System
    @typ : ComponentType

    def initialize(@world, @typ)
      super(@world)
      @world.register_singleframe_deleter(@typ)
    end

    def execute
      @world.base_pool_for(@typ).clear
    end
  end

  # Group of systems to process `EcsWorld` instance.
  # You can add Systems to Systems to create hierarchy.
  # You can either create Systems directly or (preferred way) inherit from `ECS::Systems` to add systems in `initialize`
  class Systems < System
    # List of systems in a group. This list shouldn't be modified directly.
    # Instead, use `#add` to add systems to it and `ECS::System#active` to disable systems
    getter children = [] of System
    @filters = [] of Filter?
    @cur_child : System?

    def initialize(@world : World)
      @started = false
    end

    # Adds system to a group
    def add(sys : System)
      children << sys
      if @started
        sys.init
        @filters << sys.filter(@world).as(Filter | Nil)
      end
      self
    end

    # Creates system and adds it to a group
    def add(sys : System.class)
      add(sys.new(@world))
    end

    # Adds `RemoveAllOf` instance for specified copmonent type
    def remove_singleframe(typ)
      add(ECS::RemoveAllOf.new(@world, typ))
    end

    def init
      raise "#{self.class} already initialized" if @started
      @children.each do |child|
        # puts "#{child.class.name}.init begin"
        child.init
        # puts "#{child.class.name}.init end"
      end
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

  # prints total count of registered components and classes of systems.
  macro debug_stats
    {% puts "total components: #{Component.all_subclasses.size}" %}
    {% puts "    single frame: #{Component.all_subclasses.select { |x| x.annotation(SingleFrame) }.size}" %}
    {% puts "    multiple: #{Component.all_subclasses.select { |x| x.annotation(MultipleComponents) }.size}" %}
    {% puts "    singleton: #{Component.all_subclasses.select { |x| x.annotation(SingletonComponent) }.size}" %}
    {% puts "total systems: #{System.all_subclasses.size}" %}
  end
end

class LinkedList
  @array : Array(Int32)
  @root = 0
  getter remaining = 0
  getter count = 0

  def initialize(@count : Int32)
    @remaining = @count
    # initialize with each element pointing to next
    @array = Array(Int32).new(@count) { |i| i + 1 }
  end

  def next_item
    result = @root
    raise "linked list empty" if result >= @count
    @root = @array[@root]
    @remaining -= 1
    result
  end

  def release(item : Int32)
    @array[item] = @root
    @remaining += 1
    @root = item
  end

  def resize(new_size)
    raise "shrinking list isn't supported" if new_size < @count
    (new_size - @count).times do |i|
      @array << i + @count + 1
    end
    @remaining += new_size - @count
    @count = new_size
  end

  def clear
    @remaining = @count
    @count.times do |i|
      @array[i] = i + 1
    end
    @root = 0
  end
end
