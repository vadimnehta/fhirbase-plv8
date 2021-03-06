drop table if exists  _valueset_expansion;
create table _valueset_expansion  (
    id serial primary key,
    valueset_id text not null,
    parent_code text,
    system text not null,
    abstract boolean,
    definition text,
    designation jsonb,
    extension jsonb,
    code text not null,
    display text
);

DO $JS$
   var log = function(x){plv8.elog(NOTICE, x)}

   function expand_concept(acc, props, parent, concept){
        acc.push({
            valueset_id: props.valueset_id,
            system: props.system,
            parent_code: parent.code,
            code: concept.code,
            display: concept.display,
            definition: concept.definition,
            abstract: concept.abstract,
            designation: JSON.stringify(concept.designation),
            extension: JSON.stringify(concept.estension)
        })

        if(concept.concept){
            var cnt = concept.concept.length
            for(var i = 0; i < cnt; i++){
                expand_concept(acc, props, concept, concept.concept[i])
            }
        }
        return acc
   };

   function expand(vs){
        var acc = [];
        var codeSystem = vs.codeSystem;
        var props = { valueset_id: vs.id };
        if(codeSystem && codeSystem.concept) {
            props.system = codeSystem.system;
            var cnt = codeSystem.concept.length
            for(var i = 0; i < cnt; i++){
                expand_concept(acc, props, {}, codeSystem.concept[i]);
            }
        }
        var includes = vs.compose && vs.compose.include
        if(includes){
            var cnt = includes.length
            for(var i = 0; i < cnt; i++){
                var include = includes[i]
                props.system = include.system;
                for(var j = 0; j < (include.concept && include.concept.length) || 0; j++){
                    expand_concept(acc, props, {}, include.concept[j]);
                }
            }
        }
        return acc;
   }

   function parse(x){
     if(typeof x === 'string'){
       return JSON.parse(x);
     }else{
       return x;
     }
   }

   var plan = plv8.prepare( 'SELECT * FROM valueset');
   var cursor = plan.cursor();
   var row = null;
   while (row = cursor.fetch()) {
     var res = expand(parse(row.resource))
     if(res.length > 0){
        log('expand valueset: ' + row.resource.id + ' (' + res.length + ')')
        plv8.execute(
            "INSERT INTO _valueset_expansion" +
            "(valueset_id, system, parent_code, code, display, abstract, definition, designation, extension) " +
            "SELECT x->>'valueset_id', x->>'system', x->>'parent_code', x->>'code', x->>'display', (x->>'abstract')::boolean, x->>'definition', (x->'designation')::jsonb, (x->'extension')::jsonb " +
            "FROM json_array_elements($1::json) x"
        , JSON.stringify(res))
     }
   }
   cursor.close();
   plan.free();

$JS$ LANGUAGE plv8;


-- just experiment
drop table if exists  _fhirbase_hook;
create table _fhirbase_hook  (
    id serial primary key,
    function_name text not null,
    system boolean default false,
    phase text not null,
    hook_function_name text not null,
    weight integer
);

CREATE INDEX idx_valueset_expansion_ilike ON _valueset_expansion  USING GIN (code gin_trgm_ops, display gin_trgm_ops);
CREATE INDEX idx_valueset_valuset_id ON _valueset_expansion (valueset_id);
