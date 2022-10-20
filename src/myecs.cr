require "cannon"

module ECS
  # :nodoc:
  COMP_INDICES = {} of Component.class => Int32

  # Component - container for user data without / with small logic inside.
  # All components should be inherited from `ECS::Component`
  @[Packed]
  abstract struct Component
    include Cannon::Auto

    macro inherited
      {% ECS::COMP_INDICES[@type] = ECS::COMP_INDICES.size %}

      @[AlwaysInline]
      def self.component_index
        {{ECS::COMP_INDICES[@type]}}
      end
    end
  end

  # Represents component that should exist for one frame and be deleted after.
  annotation SingleFrame
  end

  # Represents component that doesn't belong to specific entity. Instead, it can be acquired from every entity.
  annotation Singleton
  end

  # Represents component that can be present on any entity more than once.
  annotation Multiple
  end

  private SMALL_COMPONENT_POOL_SIZE =   16
  private DEFAULT_ENTITY_POOL_SIZE  = 1024

  # Entity Identifier
  alias EntityID = UInt32

  # Identifier that doesn't match any entity
  NO_ENTITY = 0xFFFFFFFFu32

  # Сontainer for components. Consists from UInt64 and pointer to `World`
  struct Entity
    # ID of entity
    getter id : EntityID
    # World that contains entity
    getter world : World

    protected def initialize(@world, @id)
    end

    # Adds component to the entity.
    # Will raise if component already exists (and doesn't have `Multiple` annotation)
    def add(comp : Component)
      @world.pool_for(comp).add_component(@id, comp)
      self
    end

    # Adds component to the entity or update existing component of same type
    def set(comp : Component)
      @world.pool_for(comp).add_or_update_component(@id, comp)
      self
    end

    # Returns true if component of type `typ` exists on the entity
    def has?(typ : ComponentType)
      @world.base_pool_for(typ).has_component?(@id)
    end

    # Removes component of type `typ` from the entity. Will raise if component isn't present on entity
    def remove(typ : ComponentType)
      @world.base_pool_for(typ).remove_component(@id)
      self
    end

    # Removes component of type `typ` from the entity if it exists. Otherwise, do nothing
    def remove_if_present(typ : ComponentType)
      @world.base_pool_for(typ).try_remove_component(@id)
      self
    end

    # Deletes component of type `typ` and add component `comp` to the entity
    def replace(typ : ComponentType, comp : Component)
      @world.base_pool_for(typ).remove_component(@id, dont_gc: true)
      add(comp)
    end

    def inspect(io)
      io << "Entity{" << id << "}["
      @world.pools.each { |pool| io << pool.name << "," if pool.has_component?(@id) && !pool.is_singleton }
      io << "]"
    end

    # Update existing component of same type on the entity. Will raise if component of this type isn't present.
    def update(comp : Component)
      @world.pool_for(comp).update_component(@id, comp)
    end

    # Destroys entity removing all components from it.
    # Entity ID is marked as free and can be reused
    def destroy
      @world.pools.each do |pool|
        # break if @world.count_components[@id] <= World::ENTITY_EMPTY #seems to be slower
        pool.try_remove_component(@id, dont_gc: true)
      end
      @world.gc_entity @id
    end

    # Destroys entity if it is empty. It is done automatically when last component is removed
    # So the only use case is when you create entity then want to destroy if no components was added to it.
    def destroy_if_empty
      @world.check_gc_entity @id
    end

    macro finished
      {% for obj in Component.all_subclasses %} 
      {% obj_name = obj.id.split("::").last.id %}
      def get{{obj_name}}
        @world.pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}})).get_component?(@id) || raise "{{obj}} not present on entity #{self}"
      end
  
      def get{{obj_name}}?
        @world.pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}})).get_component?(@id)
      end

      def get{{obj_name}}_ptr
        @world.pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}})).get_component_ptr(@id)
      end
      {% end %}
    end
  end

  # type that represents type of any component
  alias ComponentType = Component.class

  private abstract class BasePool
    def total_count : Int32
      @used
    end

    @size : Int32
    @used : Int32 = 0
    @corresponding : Slice(EntityID)
    @sparse : Slice(Int32)
    @cache_entity : EntityID = NO_ENTITY
    @cache_index : Int32 = -1
    property deleter_registered = false

    def initialize(@size, @world : World)
      @sparse = Pointer(Int32).malloc(@world.entities_capacity).to_slice(@world.entities_capacity)
      @sparse.fill(-1)
      @corresponding = Pointer(EntityID).malloc(@size).to_slice(@size)
    end

    protected def resize_sparse(count)
      old = @sparse.size
      @sparse = @sparse.to_unsafe.realloc(count).to_slice(count)
      (old...count).each do |i|
        @sparse[i] = -1
      end
    end

    protected def grow
      old_size = @size
      @size = case old_size
              when 0
                1
              when 1
                SMALL_COMPONENT_POOL_SIZE
              else
                @size * 2
              end
      @raw = @raw.to_unsafe.realloc(@size).to_slice(@size)
      @corresponding = @corresponding.to_unsafe.realloc(@size).to_slice(@size)
    end

    private def release_index(index)
      unless index == @used - 1
        fix_entity = @corresponding[@used - 1]
        @sparse[fix_entity] = index
        @corresponding[index] = fix_entity
      end
      @used -= 1
    end

    protected def get_free_index : Int32
      @used += 1
      grow if @used >= @size
      @used - 1
    end

    def entity_to_id(ent : EntityID) : Int32
      return @cache_index if @cache_entity == ent
      @sparse[ent]
    end

    def has_component?(entity) : Bool
      return true if entity == @cache_entity
      @sparse[entity] >= 0
    end

    def remove_component(entity, *, dont_gc = false)
      raise "can't remove component #{self.class} from #{Entity.new(@world, entity)}" unless has_component?(entity)
      remove_component_without_check(entity)
      @world.dec_count_components(entity, dont_gc)
    end

    def try_remove_component(entity, *, dont_gc = false)
      return unless has_component?(entity)
      remove_component_without_check(entity)
      @world.dec_count_components(entity, dont_gc)
    end

    def remove_component_without_check_single(entity)
      item = entity_to_id entity
      comp = @raw[item]
      if comp.responds_to?(:when_removed)
        comp.when_removed(Entity.new(@world, entity))
      end
      @cache_entity = NO_ENTITY if @cache_index == item || @cache_index == @used - 1
      @sparse[entity] = -1
      release_index item
    end

    def remove_component_without_check_multiple(entity)
      (0...@used).each do |i|
        if @corresponding[i] == entity
          comp = @raw[i]
          if comp.responds_to?(:when_removed)
            comp.when_removed(Entity.new(@world, entity))
          end
        end
      end
      @cache_entity = NO_ENTITY # because many entites are affected
      @sparse[entity] = -1
      # we just iterate over all array
      # TODO - faster method
      (@used - 1).downto(0) do |i|
        if @corresponding[i] == entity
          release_index i
        end
      end
    end

    def each_entity(& : EntityID ->)
      i = 0
      @used.times do |iter|
        break if i >= @used
        ent = @corresponding[i]
        @cache_index = i
        @cache_entity = ent
        yield(ent)
        i += 1 if @corresponding[i] == ent
      end
    end

    def clear(with_callbacks = false)
      @sparse.fill(-1)
      @used = 0
      @cache_entity = NO_ENTITY
    end
  end

  private abstract class Pool(T) < BasePool
    def name
      T.to_s
    end

    abstract def remove_component_without_check(entity)
    abstract def update_component(entity, comp)
    abstract def add_component(entity, comp)
    abstract def add_or_update_component(entity, comp)
    abstract def get_component_ptr(entity)
    abstract def get_component?(entity)
  end

  private class SingletonPool(T) < Pool(T)
    @raw = uninitialized T

    def initialize(@world : World)
      super(1, @world)
    end

    def is_singleton
      true
    end

    def has_component?(entity) : Bool
      @used > 0
    end

    def remove_component(entity, *, dont_gc = false)
      raise "can't remove singleton #{self.class}" if @used == 0
      item = @raw
      if item.responds_to?(:when_removed)
        item.when_removed(Entity.new(@world, entity))
      end
      @used = 0
    end

    def remove_component_without_check(entity)
    end

    def each_entity(& : EntityID ->)
    end

    def clear(with_callbacks = false)
      if @used > 0 && @raw.responds_to?(:when_removed)
        item = @raw
        if item.responds_to?(:when_removed)
          item.when_removed(Entity.new(@world, NO_ENTITY))
        end
      end
      @used = 0
    end

    def update_component(entity, comp)
      @used = 1
      @raw = comp.as(Component).as(T)
    end

    def add_component(entity, comp)
      @used = 1
      @raw = comp.as(Component).as(T)
      item = @raw
      if item.responds_to?(:when_added)
        item.when_added(Entity.new(@world, entity))
      end
    end

    def add_or_update_component(entity, comp)
      was_empty = @used == 0
      @used = 1
      @raw = comp.as(Component).as(T)
      if was_empty
        if comp.responds_to?(:when_added)
          comp.when_added(Entity.new(@world, entity))
        end
      end
    end

    def get_component_ptr(entity)
      pointerof(@raw)
    end

    def get_component?(entity)
      return nil if @used == 0
      @raw
    end

    def encode(io)
      Cannon.encode(io, @used)
      Cannon.encode(io, @raw)
    end

    def decode(io)
      @used = Cannon.decode(io, typeof(@used))
      @raw = Cannon.decode(io, typeof(@raw))
    end
  end

  private class NormalPool(T) < Pool(T)
    @raw : Slice(T)

    def initialize(@world : World)
      size = 0
      super(size, @world)
      @raw = Pointer(T).malloc(@size).to_slice(@size)
    end

    def name
      T.to_s
    end

    def is_singleton
      false
    end

    private def release_index(index)
      unless index == @used - 1
        @raw[index] = @raw[@used - 1]
      end
      super
    end

    protected def grow
      super
      @raw = @raw.to_unsafe.realloc(@size).to_slice(@size)
    end

    def remove_component_without_check(entity)
      {% if T.annotation(ECS::Multiple) %}
        remove_component_without_check_multiple(entity)
      {% else %}
        remove_component_without_check_single(entity)
      {% end %}
    end

    def pointer
      @raw
    end

    def add_component_without_check(entity : EntityID, item)
      {% if T.annotation(ECS::Multiple) %}
        @world.inc_count_components(entity) unless has_component?(entity)
      {% else %}
        @world.inc_count_components(entity)
      {% end %}
      fresh = get_free_index
      pointer[fresh] = item.as(Component).as(T)
      @sparse[entity] = fresh
      @cache_entity = entity
      @cache_index = fresh
      @corresponding[fresh] = entity
      if item.responds_to?(:when_added)
        item.when_added(Entity.new(@world, entity))
      end
    end

    def update_component(entity, comp)
      pointer[entity_to_id(entity)] = comp.as(Component).as(T)
    end

    def add_component(entity, comp)
      {% if !T.annotation(ECS::Multiple) %}
        raise "#{T} already added to #{Entity.new(@world, entity)}" if has_component?(entity)
      {% end %}
      {% if T.annotation(ECS::SingleFrame) && (!T.annotation(ECS::SingleFrame).named_args.keys.includes?("check".id) || T.annotation(ECS::SingleFrame)[:check]) %}
        raise "#{T} is created but never deleted" unless @deleter_registered
      {% end %}
      add_component_without_check(entity, comp)
    end

    def add_or_update_component(entity, comp)
      if has_component?(entity)
        update_component(entity, comp)
      else
        {% if T.annotation(ECS::SingleFrame) && (!T.annotation(ECS::SingleFrame).named_args.keys.includes?("check".id) || T.annotation(ECS::SingleFrame)[:check]) %}
          raise "#{T} is created but never deleted" unless @deleter_registered
        {% end %}
        add_component_without_check(entity, comp)
      end
    end

    def get_component_ptr(entity)
      (pointer + entity_to_id entity).to_unsafe
    end

    def get_component?(entity)
      return nil unless has_component?(entity)
      pointer[entity_to_id entity]
    end

    def encode(io)
      Cannon.encode(io, @used)
      Cannon.encode(io, @size)
      Cannon.encode(io, @sparse.size)
      if @used >= @sparse.size//2
        Cannon.encode(io, @sparse)
      else
        n = 0
        @sparse.each_with_index do |v, i|
          next if @sparse[i] == -1
          n += 1
          Cannon.encode(io, i)
          Cannon.encode(io, v)
        end
        Cannon.encode(io, -1)
      end
      @used.times do |i|
        Cannon.encode(io, @corresponding[i])
      end
      @used.times do |i|
        Cannon.encode(io, @raw[i])
      end
    end

    def decode(io)
      @used = Cannon.decode(io, typeof(@used))
      @size = Cannon.decode(io, typeof(@size))
      n = Cannon.decode(io, typeof(@sparse.size))
      if @used >= n//2
        @sparse = Cannon.decode(io, typeof(@sparse))
      else
        @sparse = Pointer(Int32).malloc(n).to_slice(n)
        @sparse.fill(-1)
        @used.times do
          i = Cannon.decode(io, Int32)
          v = Cannon.decode(io, Int32)
          @sparse[i] = v
        end
        raise "incorrect sparse count for pool #{self}" unless Cannon.decode(io, Int32) == -1
      end
      @corresponding = Pointer(EntityID).malloc(@size).to_slice(@size)
      @used.times do |i|
        @corresponding[i] = Cannon.decode(io, EntityID)
      end
      @raw = Pointer(T).malloc(@size).to_slice(@size)
      @used.times do |i|
        @raw[i] = Cannon.decode(io, T)
      end
      @cache_entity = NO_ENTITY
      @cache_index = -1
    end

    def clear(with_callbacks = false)
      if with_callbacks && @used > 0 && @raw[0].responds_to?(:when_removed)
        @used.times do |i|
          item = @raw[i]
          if item.responds_to?(:when_removed)
            item.when_removed(Entity.new(@world, @corresponding[i]))
          end
        end
      end
      super
    end
  end

  # Root level container for all entities / components, is iterated with `ECS::Systems`
  class World
    @free_entities = LinkedList.new(DEFAULT_ENTITY_POOL_SIZE)
    protected getter count_components = Slice(UInt16).new(DEFAULT_ENTITY_POOL_SIZE)
    protected getter pools = Array(BasePool).new({{Component.all_subclasses.size}})

    @@comp_can_be_multiple = Set(ComponentType).new

    protected def register_singleframe_deleter(typ)
      base_pool_for(typ).deleter_registered = true
    end

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

    # total number of alive entities in a world
    def entities_count
      @free_entities.count - @free_entities.remaining
    end

    # number of entities that could exist in a world before reallocation of pools
    def entities_capacity
      @free_entities.count
    end

    # Creates new entity in a world context.
    # Basically doesn't cost anything as it just increase entities counter.
    # Entity don't take up space without components.
    def new_entity
      if @free_entities.remaining <= 0
        n = @free_entities.count*2
        @free_entities.resize(n)
        @count_components = @count_components.to_unsafe.realloc(n).to_slice(n)
        @pools.each &.resize_sparse(n)
      end
      id = @free_entities.next_item
      @count_components[id] = ENTITY_EMPTY
      Entity.new(self, EntityID.new(id))
    end

    # Creates new Filter.
    # This call can be skipped:
    # Instead of `world.new_filter.of(Comp1)` you can do `world.of(Comp1)`
    def new_filter
      Filter.new(self)
    end

    # Deletes all components and entities from the world
    def delete_all(with_callbacks = false)
      @pools.each &.clear(with_callbacks)
      @free_entities.clear
      @count_components.fill(ENTITY_DELETED)
    end

    # Iterates over all entities
    def each_entity(& : Entity ->)
      entities_capacity.times do |i|
        next if @count_components[i] <= ENTITY_EMPTY
        yield(Entity.new(self, EntityID.new(i)))
      end
    end

    private ENTITY_DELETED = 0u16
    private ENTITY_EMPTY   = 1u16

    @[AlwaysInline]
    protected def inc_count_components(entity_id)
      raise "adding component to deleted entity: #{entity_id}" if @count_components[entity_id] == ENTITY_DELETED
      @count_components[entity_id] &+= 1
      # raise "BUG: inc_count_components failed" if @count_components[entity_id] > pools.size
    end

    @[AlwaysInline]
    protected def dec_count_components(entity_id, dont_gc)
      # raise "BUG: dec_count_components failed" if @count_components[entity_id] <= ENTITY_EMPTY
      @count_components[entity_id] &-= 1
      if @count_components[entity_id] == ENTITY_EMPTY && !dont_gc
        @count_components[entity_id] = ENTITY_DELETED
        gc_entity(entity_id)
      end
    end

    # Returns true if at least one component of type `typ` exists in a world
    def component_exists?(typ)
      base_pool_for(typ).total_count > 0
    end

    # Returns SimpleFilter (stack-allocated) that can iterate over single component
    def query(typ)
      SimpleFilter.new(self, typ)
    end

    @[AlwaysInline]
    protected def check_gc_entity(entity)
      @free_entities.release(Int32.new(entity)) if @count_components[entity] == ENTITY_DELETED
    end

    @[AlwaysInline]
    protected def gc_entity(entity)
      @free_entities.release(Int32.new(entity))
    end

    macro finished
      private def init_pools
        {% for index in 1..COMP_INDICES.size %} 
          @pools << nil.unsafe_as(BasePool)
        {% end %}

        {% for obj, index in Component.all_subclasses %} 
          {% if obj.annotation(ECS::Singleton) %}
            @pools[{{COMP_INDICES[obj]}}] = SingletonPool({{obj}}).new(self) 
          {% else %}
            @pools[{{COMP_INDICES[obj]}}] = NormalPool({{obj}}).new(self) 
          {% end %}


          {% if obj.annotation(ECS::Multiple) %}
            @@comp_can_be_multiple.add {{obj}}
          {% end %}
        {% end %}
      end

      {% for obj in Component.all_subclasses %} 
        @[AlwaysInline]
        protected def pool_for(component : {{obj}}) : Pool({{obj}})
          @pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}}))
        end

        {% if obj.annotation(ECS::Singleton) %}
          {% obj_name = obj.id.split("::").last.id %}
          def get{{obj_name}}
          @pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}})).get_component?(Entity.new(self, NO_ENTITY)) || raise "{{obj}} was not created"
          end
      
          def get{{obj_name}}?
            @pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}})).get_component?(Entity.new(self, NO_ENTITY))
          end
    
          def get{{obj_name}}_ptr
            @pools[{{COMP_INDICES[obj]}}].as(Pool({{obj}})).get_component_ptr(Entity.new(self, NO_ENTITY))
          end
        {% end %}
    
      {% end %}

      @[AlwaysInline]
      protected def base_pool_for(typ : ComponentType)
        @pools[typ.component_index]
      end

      # Non-allocating version of `stats`. Yields component names and count of corresponding components
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

    # @free_entities = LinkedList.new(DEFAULT_ENTITY_POOL_SIZE)
    # protected getter count_components = Slice(UInt16).new(DEFAULT_ENTITY_POOL_SIZE)
    # protected getter pools = Array(BasePool).new({{Component.all_subclasses.size}})
    def encode(io)
      Cannon.encode(io, @free_entities)
      Cannon.encode(io, @count_components)
      @pools.each &.encode(io)
    end

    def decode(io)
      @free_entities = Cannon.decode(io, typeof(@free_entities))
      @count_components = Cannon.decode(io, typeof(@count_components))
      @pools.each &.decode(io)
    end
  end

  # General filter class, contain methods existing both in `Filter` (fully functional filter) and `SimpleFilter` (simple stack-allocated filter)
  module AbstractFilter
    include Enumerable(Entity)

    # returns true if entity satisfy filter
    abstract def satisfy(entity : Entity) : Bool
  end

  # Stack allocated filter - can iterate over one component type.
  struct SimpleFilter
    include AbstractFilter
    @pool : BasePool

    # type of components that this filter iterate
    getter typ : ComponentType
    # world that owns this filtetr
    getter world : World

    # Creates SimpleFilter. An easier way is to do `world.query(typ)`
    def initialize(@world, @typ)
      @pool = @world.base_pool_for(@typ)
    end

    # returns true if entity satisfy filter (contain a component `typ`)
    def satisfy(entity : Entity) : Bool
      entity.has? @typ
    end

    # Returns number of entities that match the filter. (in fact - number of components `typ` in a world)
    def size
      @pool.total_count
    end

    # iterates over all entities containing component `typ`
    # Note that for `Multiple` same entity can be yielded multiple times, once for each component present on entity
    def each(& : Entity ->)
      @pool.each_entity do |entity|
        yield(Entity.new(@world, entity))
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
          raise "iterating over several Multiple isn't supported: #{list}"
        elsif old = @all_multiple_component
          raise "iterating over several Multiple isn't supported: #{old} and #{multiple}"
        elsif old = @any_multiple_component_index
          raise "iterating over several Multiple isn't supported: #{@any_of[old]} and #{multiple}"
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
          raise "iterating over several Multiple isn't supported: #{old} and #{item}"
        elsif old = @any_multiple_component_index
          raise "iterating over several Multiple isn't supported: #{@any_of[old]} and #{item}"
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
          raise "iterating over several Multiple isn't supported: #{list}"
        elsif old = @all_multiple_component
          raise "iterating over several Multiple isn't supported: #{old} and #{multiple}"
        elsif old = @any_multiple_component_index
          raise "iterating over several Multiple isn't supported: #{@any_of[old]} and #{multiple}"
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
    def filter(&block : Entity -> Bool)
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
      @world.base_pool_for(typ).each_entity do |id|
        entity = Entity.new(@world, id)
        next unless satisfy(entity)
        yield(entity)
      end
    end

    private def iterate_over_list(list, & : Entity ->)
      list.each_with_index do |typ, index|
        @world.base_pool_for(typ).each_entity do |id|
          entity = Entity.new(@world, id)
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
    # Note that for `Multiple` same entity can be called multiple times, once for each component present on entity
    def each(& : Entity ->)
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
      elsif smallest_any && (@any_multiple_component_index || smallest_any_count < @world.entities_count // 2)
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
    # If this method is present, it should return a filter that will be applied to a world
    # It can also return `nil` that means that no filter is present and #process won't be called
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
  # This is a recommended way of deleting `SingleFrame` components,
  # as library can detect if such system exists and raise exception if it doesn't.
  # Example:
  # ```
  # systems.add(ECS::RemoveAllOf.new(@world, Component1))`
  # ```
  # or use a shortcut:
  # ```
  # systems.remove_singleframe(Component1)
  # ```
  #
  class RemoveAllOf < System
    @typ : ComponentType

    # creates a system for a given `world` and components of type `typ`
    def initialize(@world, @typ)
      super(@world)
      @world.register_singleframe_deleter(@typ)
    end

    # :nodoc:
    def filter(world)
      @world.of(@typ)
    end

    # :nodoc:
    def process(entity)
      entity.remove(@typ)
    end
  end

  # Group of systems to process `EcsWorld` instance.
  # You can add Systems to Systems to create hierarchy.
  # You can either create Systems directly or (preferred way) inherit from `ECS::Systems` to add systems in `initialize`
  class Systems < System
    # List of systems in a group. This list must not be modified directly.
    # Instead, use `#add` to add systems to it and `ECS::System#active` to disable systems
    getter children = [] of System
    @filters = [] of Filter?
    @cur_child : System?

    # creates empty `Systems` group.
    # This method should be overriden in children to automatically add systems.
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

    # Creates system of given class and adds it to a group
    def add(sys : System.class)
      add(sys.new(@world))
    end

    # Adds `RemoveAllOf` instance for specified component type
    def remove_singleframe(typ)
      add(ECS::RemoveAllOf.new(@world, typ))
    end

    # calls `init` for all children systems
    # also initializes filters for children systems
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

    # calls `execute` and `process` for all active children
    def execute
      raise "#{@children.map(&.class)} wasn't initialized" unless @started
      @children.zip(@filters) do |sys, filter|
        @cur_child = sys
        if filter && sys.active
          filter.each { |ent| sys.process(ent) }
        end
        sys.do_execute
      end
    end

    # calls `teardown` for all children systems
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
    {% puts "    multiple: #{Component.all_subclasses.select { |x| x.annotation(Multiple) }.size}" %}
    {% puts "    singleton: #{Component.all_subclasses.select { |x| x.annotation(Singleton) }.size}" %}
    {% puts "total systems: #{System.all_subclasses.size}" %}
  end
end

# :nodoc:
class ECS::LinkedList
  include Cannon::Auto
  @array : Slice(Int32)
  @root = 0
  getter remaining = 0
  getter count = 0

  protected def initialize(@array, @root, @remaining, @count)
  end

  def initialize(@count : Int32)
    @remaining = @count
    # initialize with each element pointing to next
    @array = Slice(Int32).new(@count) { |i| i + 1 }
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
    @array = @array.to_unsafe.realloc(new_size).to_slice(new_size)
    (@count...new_size).each do |i|
      @array[i] = i + 1
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
