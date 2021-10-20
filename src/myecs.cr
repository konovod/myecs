require "./utils"

module ECS
  annotation SingleFrame
  end

  annotation SingletonComponent
  end

  abstract struct Component
  end

  DEFAULT_COMPONENT_POOL_SIZE   =  1024
  DEFAULT_EVENT_POOL_SIZE       =    16
  DEFAULT_EVENT_TOTAL_POOL_SIZE =  1024
  DEFAULT_ENTITY_POOL_SIZE      = 16384

  alias EntityID = UInt32
  NO_ENTITY = 0u32

  struct Entity
    getter id : EntityID
    getter world : World

    protected def initialize(@world, @id)
    end

    def add(comp : Component)
      raise "#{comp.class} already added" if has?(comp.class)
      @world.pool_for(comp).add_or_update_component(self, comp)
      self
    end

    def set(comp : Component)
      @world.pool_for(comp).add_or_update_component(self, comp)
      self
    end

    def has?(typ : ComponentType)
      @world.pools.has_key?(typ) && @world.pools[typ].has_component?(self)
    end

    def remove(typ : ComponentType)
      @world.pools[typ].remove_component(self)
      self
    end

    def remove_if_present(typ : ComponentType)
      @world.pools[typ].try_remove_component(self)
      self
    end

    def replace(typ : ComponentType, comp : Component)
      remove(typ)
      add(comp)
    end

    def update(comp : Component)
      @world.pool_for(comp).update_component(self, comp)
    end

    def destroy
      @world.pools.each_value do |pool|
        pool.try_remove_component(self)
      end
    end

    macro finished
      {% for obj in Component.all_subclasses %} 
      {% obj_name = obj.id.split("::").last.id %}
      def get{{obj_name}}
        raise "not found" unless @world.pools.has_key? {{obj}}
        @world.pools[{{obj}}].as(Pool({{obj}})).get_component(self)
      end
  
      def get{{obj_name}}?
        return nil unless @world.pools.has_key? {{obj}}
        @world.pools[{{obj}}].as(Pool({{obj}})).get_component?(self)
      end
      def get{{obj_name}}_ptr
      raise "not found" unless @world.pools.has_key? {{obj}}
      @world.pools[{{obj}}].as(Pool({{obj}})).get_component_ptr(self)
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

  enum KeyOperation
    AddKey
    RemoveKey
    Clear
  end

  class Pool(T) < BasePool
    @size : Int32
    @used : Int32 = 0
    @raw : Pointer(T)
    @corresponding : Pointer(EntityID)
    @sparse = Hash(EntityID, Int32).new
    @sparse_keys = Set(EntityID).new
    @sparse_operations = Array(Tuple(KeyOperation, EntityID)).new
    @free_items = LinkedList.new(1)
    @single_frame_freed : Int32 = 0
    @unsafe_iterating = 0

    def initialize(@world : World, @size)
      {% if T.annotation(ECS::SingletonComponent) %}
        @size = 1
      {% end %}
      @raw = Pointer(T).malloc(@size)
      @corresponding = Pointer(EntityID).malloc(@size)
      {% if !T.annotation(ECS::SingleFrame) %}
        @free_items = LinkedList.new(@size)
      {% end %}
    end

    private def get_free_index : Int32
      @used += 1
      grow if @used >= @size
      {% if T.annotation(ECS::SingleFrame) %}
        @used - 1
      {% else %}
        @free_items.next_item
      {% end %}
    end

    private def release_index(index)
      {% if T.annotation(ECS::SingleFrame) %}
        raise "incorrect deletion order for #{self.class}: #{index} #{@single_frame_freed}" unless index == @single_frame_freed
        @single_frame_freed += 1
        if @single_frame_freed >= @used
          @single_frame_freed = 0
          @used = 0
        end
      {% else %}
        @free_items.release(index)
        @used -= 1
      {% end %}
    end

    def total_count : Int32
      @used - @single_frame_freed
    end

    private def grow
      @size = @size * 2
      @raw = @raw.realloc(@size)
      @corresponding = @corresponding.realloc(@size)
      {% if !T.annotation(ECS::SingleFrame) %}
        @free_items.resize(@size)
      {% end %}
    end

    def has_component?(entity) : Bool
      {% if T.annotation(ECS::SingletonComponent) %}
        true
      {% else %}
        @sparse.has_key? entity.id
      {% end %}
    end

    def remove_component(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        raise "can't remove singleton from #{self.class}"
      {% else %}
        raise "can't remove component from #{self.class}" unless has_component?(entity)
        item = @sparse[entity.id]
        @corresponding[item] = NO_ENTITY
        @sparse.delete entity.id
        if @unsafe_iterating > 0
          @sparse_operations << {KeyOperation::RemoveKey, entity.id}
        else
          @sparse_keys.delete entity.id
        end
        release_index item
      {% end %}
    end

    def try_remove_component(entity)
      {% if !T.annotation(ECS::SingletonComponent) %}
        return unless has_component?(entity)
        item = @sparse[entity.id]
        @corresponding[item] = NO_ENTITY
        @sparse.delete entity.id
        if @unsafe_iterating > 0
          @sparse_operations << {KeyOperation::RemoveKey, entity.id}
        else
          @sparse_keys.delete entity.id
        end
        release_index item
      {% end %}
    end

    def each_entity(& : Entity ->)
      {% if !T.annotation(ECS::SingletonComponent) %}
        @unsafe_iterating += 1
        begin
          @sparse_keys.each do |k|
            yield(Entity.new(@world, k))
          end
        ensure
          @unsafe_iterating -= 1
          if @unsafe_iterating == 0
            @sparse_operations.each do |(op, id)|
              case op
              when .add_key?
                @sparse_keys << id
              when .remove_key?
                @sparse_keys.delete id
              when .clear?
                @sparse_keys.clear
              end
            end
            @sparse_operations.clear
          end
        end
      {% end %}
    end

    def clear
      {% if T.annotation(ECS::SingletonComponent) %}
      {% elsif T.annotation(ECS::SingleFrame) %}
        if @unsafe_iterating > 0
          @sparse_operations << {KeyOperation::Clear, NO_ENTITY}
        else
          @sparse_keys.clear
        end
        @used = @single_frame_freed = 0
        @sparse.clear
      {% else %}
        if @unsafe_iterating > 0
          @sparse_operations << {KeyOperation::Clear, NO_ENTITY}
        else
          @sparse_keys.clear
        end
        if @used >= @size / 4
          @sparse.clear
          @free_items.clear
          @used = 0
        else
          each_entity { |x| remove_component x }
        end
      {% end %}
    end

    def pointer
      @raw
    end

    def add_component(entity : Entity, item)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer[0] = item.as(T)
      {% else %}
      fresh = get_free_index
      pointer[fresh] = item.as(T)
      @sparse[entity.id] = fresh
      if @unsafe_iterating > 0
        @sparse_operations << {KeyOperation::AddKey, entity.id}
      else
        @sparse_keys << entity.id
      end
      @corresponding[fresh] = entity.id
      {% if T.annotation(ECS::SingleFrame) %}
        @world.add_remover(entity, T)
      {% end %}
      {% end %}
    end

    def get_component(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer[0]
      {% else %}
        pointer[@sparse[entity.id]]
      {% end %}
    end

    def update_component(entity, comp)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer[0] = comp.as(T)
      {% else %}
        pointer[@sparse[entity.id]] = comp.as(T)
      {% end %}
    end

    def add_or_update_component(entity, comp)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer[0] = comp.as(T)
      {% else %}
        if has_component?(entity)
          update_component(entity, comp)
        else
          add_component(entity, comp)
        end
      {% end %}
    end

    def get_component_ptr(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer
      {% else %}
        pointer + @sparse[entity.id]
      {% end %}
    end

    def get_component?(entity)
      {% if T.annotation(ECS::SingletonComponent) %}
        pointer[0]
      {% else %}
        return nil unless has_component?(entity)
        pointer[@sparse[entity.id]]
      {% end %}
    end
  end

  class World
    protected getter ent_id = EntityID.new(1)
    getter pools = Hash(ComponentType, BasePool).new
    property cur_systems : Systems? # TODO - TLS
    @single_frame = Queue(Tuple(EntityID, ComponentType)).new(DEFAULT_EVENT_TOTAL_POOL_SIZE)
    delegate of, all_of, any_of, exclude, to: new_filter

    def initialize
    end

    def new_entity
      Entity.new(self, @ent_id).tap { @ent_id += 1 }
    end

    def new_filter
      Filter.new(self)
    end

    def delete_all
      @pools.each_value &.clear
    end

    @processed = Set(EntityID).new(DEFAULT_ENTITY_POOL_SIZE)

    def each_entity(& : Entity ->)
      return if pools.size == 0
      @pools.each_value do |pool|
        pool.each_entity do |ent|
          next if @processed.includes? ent.id
          yield(ent)
          @processed.add(ent.id)
        end
      end
      @processed.clear
    end

    def add_remover(entity, typ)
      if sys = @cur_systems
        sys.add_remover(entity, typ)
      else
        @single_frame.push({entity.id, typ})
      end
    end

    def clear_single_frame
      while !@single_frame.empty?
        ent, typ = @single_frame.pop
        Entity.new(self, ent).remove_if_present(typ)
      end
    end

    macro finished
      {% for obj in Component.all_subclasses %} 
        def pool_for(component : {{obj}}) : Pool({{obj}})
          unless @pools.has_key? {{obj}}
            @pools[{{obj}}] = Pool({{obj}}).new(self,
                 {{obj.annotation(SingleFrame) ? DEFAULT_EVENT_POOL_SIZE : DEFAULT_COMPONENT_POOL_SIZE}}) 
          end
          @pools[{{obj}}].as(Pool({{obj}}))
        end
      {% end %}

      # def clear_single_frame
      #   {% for obj in Component.all_subclasses %} 
      #     {% if obj.annotation(SingleFrame) %}
      #       @pools[{{obj}}].clear if @pools.has_key? {{obj}}
      #     {% end %}
      #   {% end %}
      # end      
    end
  end

  class Filter
    @all_of = [] of ComponentType
    @any_of = [] of Enumerable(ComponentType)
    @exclude = [] of ComponentType
    @callbacks = [] of Proc(Entity, Bool)

    def initialize(@world : World)
    end

    def all_of(list)
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
      @all_of << item
      self
    end

    def any_of(list)
      if list.size == 1
        @all_of << list.first
        return self
      end
      raise "any_of list can't be empty" if list.size == 0
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

    def each_entity(& : Entity ->)
      smallest_all_count = 0
      smallest_any_count = 0
      if @all_of.size > 0
        return if @all_of.any? { |typ| !@world.pools.has_key? typ }
        # we use all_of and find shortest pool
        smallest_all = @all_of.min_by { |typ| @world.pools[typ].total_count }
        smallest_all_count = @world.pools[smallest_all].total_count
        return if smallest_all_count == 0
      end
      if @any_of.size > 0
        return if @any_of.any? do |list|
                    list.all? { |typ| !@world.pools.has_key? typ }
                  end
        smallest_any = @any_of.min_by do |list|
          list.sum(0) { |typ| @world.pools.has_key?(typ) ? @world.pools[typ].total_count : 0 }
        end
        smallest_any_count = smallest_any.sum(0) { |typ| @world.pools.has_key?(typ) ? @world.pools[typ].total_count : 0 }
        return if smallest_any_count == 0
      end

      if smallest_all && (!smallest_any || smallest_all_count <= smallest_any_count)
        # iterate by smallest_all
        @world.pools[smallest_all].each_entity do |entity|
          next unless satisfy(entity)
          yield(entity)
        end
      elsif smallest_any
        # iterate by smallest_any
        smallest_any.each_with_index do |typ, index|
          next unless @world.pools.has_key? typ
          @world.pools[typ].each_entity do |entity|
            next if already_processed_in_list(entity, smallest_any, index)
            next unless satisfy(entity)
            yield(entity)
          end
        end
      else
        # iterate everything
        @world.each_entity do |entity|
          next unless satisfy(entity)
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
      execute if @active
    end

    def teardown
    end

    def filter(world : World) : Filter?
      nil
    end

    def process(entity : Entity)
    end
  end

  class Systems < System
    getter children = [] of System
    @filters = [] of Filter?
    @single_frame = Queue(Tuple(System, EntityID, ComponentType)).new(DEFAULT_EVENT_TOTAL_POOL_SIZE)
    @cur_child : System?

    def initialize(@world : World)
      @started = false
    end

    def add(sys)
      children << sys
      sys.init if @started
      self
    end

    def init
      raise "#{self.class} already initialized" if @started
      @children.each &.init
      @filters = @children.map { |x| x.filter(@world).as(Filter | Nil) }
      @started = true
    end

    def add_remover(entity, typ)
      @single_frame.push({@cur_child.not_nil!, entity.id, typ})
    end

    def execute
      @world.cur_systems = self
      @children.zip(@filters) do |sys, filter|
        # check single_frame
        while !@single_frame.empty?
          asys, ent, typ = @single_frame.peek
          if asys == sys
            @single_frame.pop
            Entity.new(@world, ent).remove_if_present(typ)
          else
            break
          end
        end
        # execute system
        @cur_child = sys
        if filter && sys.active
          filter.each_entity { |ent| sys.process(ent) }
        end
        sys.do_execute
      end
      @world.cur_systems = nil
    end

    def do_execute
      if @active
        execute
      else
        # just delete all single frames
        while !@single_frame.empty?
          sys, ent, typ = @single_frame.pop
          Entity.new(@world, ent).remove_if_present(typ)
        end
      end
    end

    def teardown
      raise "#{self.class} not initialized" unless @started
      @children.each &.teardown
      @started = false
    end
  end
end
