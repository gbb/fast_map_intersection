Fast map intersection (postgis)
==============================

This [template script](https://github.com/gbb/fast_map_intersection/blob/master/fast_map_intersection.sh) will split up a large GIS map intersection query into hundreds of little pieces that run quickly in 
parallel. This is a special case; for other types of queries, try http://parpsql.com  / http://github.com/gbb/par_psql.

The script may look a little ugly - it requires a few minutes to edit a couple of variables before it can be run for your own 
query. It is very useful if you are trying to combine 2 maps - we have used this locally to reduce our intersection computation 
time from around 1 day, to just 1 hour on national scale maps with millions of rows. The results have been checked as identical. 
However, we are using 2x8-core processors, with hyperthreading...

It gives you an indication of progress as it runs, which is a nice advantage over an ordinary long-running query. You can 
optionally put extra clauses into the SQL if you need e.g. a subset of the map extracted out by some WHERE condition.

Performance features: it uses unlogged tables for temporary results; increases work_mem a bit temporarily.

Tips
=====

- Make sure you also have a good disk I/O system. See this talk: http://graemebell.net/foss4gcomo.pdf.
- Don't forget to put indices on your geo & id columns of your source tables!

How to use
==========

- Edit the 'fast_intersect.sh' file to specify your query in the query section.
- Specify the name for your result.
- Type "./fast_intersection.sh" 
- Wait a little, watch the progress bars.
- Done!
- (Press crtl-z to freeze the program if you want to inspect the command files; then 'fg' to restart).

AUTHOR
====

Graeme B Bell, Norwegian Forest and Landscape Institute / NIBIO (Norwegian Institute for Bioeconomy Research).

NEWS 
====

v1.0.1 Presented at FOSS4G Europe in Como. 


THANKS
======

- Thanks to the Norwegian Forest and Landscape Institute (now NIBIO, the Norwegian Institute of Bioeconomy Research) for 
supporting open source publication/sharing of our local scripts that may be useful for others.

- Martijn Meijers for the suggestion of using UNION ALL for a little extra speed.

TODO
====

- add more examples?
- make 'work_mem' optional (don't emit output if it's unset).
- rewrite program as a parser rather than a template script?

