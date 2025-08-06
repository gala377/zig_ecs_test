## Highlights

- Iterating making queries based in tuple of types.
- Exporting components to lua with derivation
- Accessing components from lua
- Writing systems in lua
- Hash is stored as integers in lua
- exposing a lot of fields to lua

## What next

- Creating components/entities at runtime - maybe something like command from bevy? [#Commands]
- Adding and removing components [[#Reallocating archetypes]]
- creating components/entities in lua [[#Exposing constructors to lua]]
- Lua defined components - this one is hard and not sure how to do this yet

### Commands

Commands struct would need to maybe even allocate components and entity.
It can even reserve id for it. It just needs to defer inserting it into
archetypes so it is not immediately accessible to other systems.

### Exposing more types to lua

For now the last 2 types that are exposable are structs and pointers to one element.
We could also try later to do enums and even later tagged unions but for now
we don't plan on supporting those.

Also StringHashMap and ArrayList would be useful, array list should be kinda easy
except how to identify it but other than that it is doable.

### Better components storage

Because we hold entities as archetypes we can hold components
inline as archetypes meaning as slice of slices for example.
This would speed up iterating over them as it mean that getting 
next component is just incrementing an index instead of 
doing a hashmap lookup.

It would help with cache locality. Pointer stability would be a problem when
moving entity do different archetype but as we hold components in the archetype
we don't need to hold pointers within entity anymore. 

When we move entity we can just mark the index as empty and reuse it 
later when new entity of this archetype gets created. 

### Reallocating archetypes

If some component is added or removed we need to move entity to another archetype.
Technically as scene has all entities on the heap. The archetype storage
can just simply be a map of []component_ids to pointers to entities.

### Exposing constructors to lua

-- depends on: [[#Commands]] 

Components have to be created, that means we have to expose
a method like - fromLua for components.

This can only be allowed for subset of components where
all nonnullable fields can be created from lua.

Which boils down to is every primitive type + strings.
Structs of primitive types.
Nullable types of convertible types.

Later we could technically even do enums and tagged unions.

It means for now that we just need to add generated command like
`fromLua(state: lua.State, allocator: std.mem.Allocator) !Self`.

If a component has non-default, no-lua constructible field it should probably
just throw runtime error and it should be fine.

### Lua components

-- depends on [#Commands] - without commands there is no way to create
those components (well we could hack it with like, script setup function or something like this
but you know)

We can just hold them as refs, the problem is their identity.
Meaning hash of them.
We might provide some function like `component` in lua that generates
a hash for a component and then the component is held as ref.
The problem is how ti generate this hash, we can expose a function to lua
from our runtime that has Game as context and can use the same has function.
But we somehow need to get like a unique name for the component. Maybe UUID? 
Maybe there is some way to get them deterministically for later saving of
a game state?

### Control over system execution 

Things like system groups or anything like that.
Something that would allow us to define dependencies between systems.
