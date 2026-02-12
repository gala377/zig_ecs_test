# Ideas for better editor

## Priority 1

- we should have custom rendering option for type_registry

Like for example color can use ColorEditor4 for ColorStruct
but for this we need to have custom functions for rendering.

## Priority 2

- add annotations to fields.

We should be able to add reflection_metadata where we specify that
field is readonly. This way we can make it so that entity Id 
will have read only fields. Editing those fields in general is a bad
idea.

## Priority 3

- custom field setters 

It would be cool to have custom field setters too 
so that if for example we derive some fields based on other fields 
like some data based on entity_id, we can make it so setting 
this field will update other fields.

