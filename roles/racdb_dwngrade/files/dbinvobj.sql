col owner form a20
col object_name form a30
col object_type form a30
col status form a10

select owner
,      object_name
,      object_type
,      status
from dba_invalid_objects
order by 1,2,3
;
