# Experimental prefetching SPARQL query cacher

This distribution is part of the author's ongoing Ph.D. project. 
The goal is to see if it is possible to make SPARQL queries on the Web scale better by using existing HTTP caching infrastructe as well as some simple additions, to cache full SPARQL results, partial SPARQL results, and most importantly, prefetch data into the cache and partially evaluate queries there. 

This might take some load off the servers, reduce query evaluation time as seen by the client, and help endpoints when they are down.

The present distribution seeks to implement a layer on top of an HTTP cache where the query is intercepted by a caching proxy, analyzed for cacheable and prefetchable parts, and then scheduled for prefetching. Then, it also has a component to evaluate parts of a SPARQL query and join the results.
