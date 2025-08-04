## Highlights

- Iterating making queries based in tuple of types.
- Exporting components to lua with derivation
- Accessing components from lua
- Writing systems in lua

## What next

- fix holding hashes as strings:
    lua supports 64 bit integers and will use them if the value
    fits in them so our hashes can stay as raw integers which will
    speed up iteration.


- Creating components/entities at runtime - maybe something like command from bevy? [#Commands]
- Adding and removing components [[#Reallocating archetypes]]
- creating components/entities in lua [[#Exposing constructors to lua]]
- Lua defined components - this one is hard and not sure how to do this yet

### Commands

Commands struct would need to maybe even allocate components and entity.
It can even reserve id for it. It just needs to defer inserting it into
archetypes so it is not immediately accessible to other systems.

### Reallocating archetypes

If some component is added or removed we need to move entity to another archetype.
Technically as scene has all entities on the heap. The archetype storage
can just simply be a map of []component_ids to pointers to entities.

### Exposing constructors to lua

Components have to be created, that means we have to expose
a method like - fromLua for components.

This can only be allowed for subset of components where
all nonnullable fields can be created from lua.

Which boils down to is every primitive type + strings.
Structs of primitive types.
Nullable types of convertible types.

Later we could technically even do enums and tagged unions.


### Lua components

We can just hold them as refs, the problem is their identity.
Meaning hash of them.
We might provide some function like `component` in lua that generates
a hash for a component and then the component is held as ref.
The problem is how ti generate this hash, we can expose a function to lua
from our runtime that has Game as context and can use the same has function.
But we somehow need to get like a unique name for the component. Maybe UUID? 
Maybe there is some way to get them deterministically for later saving of
a game state?


