# Fabric Language Haxe

A language adapter for haxe. 

Usage is identical to usage of [regular fabric entrypoints](https://fabricmc.net/wiki/documentation:entrypoint) however it automatically unmangles static fields. 

It's planned to add more support for unmangling, however I don't really know how haxe mangles names other than this.

This only works with entrypoints and everything else is still mangled for mixins. 
