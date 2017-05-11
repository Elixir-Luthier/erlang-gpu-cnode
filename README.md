# erlang-gpu-cnode
Demonstration of building a cnode using Cuda

build the code using the Makefile - targets are cnode_osx, cnode_linux, and cnode_gpu

```
make cnode_gpu
```

edit the Makefile with your hostname, as well as the elix.ex file and then start the server also from the Makefile

```
make serve_gpu
```
the start an iex node being certain to give it a name and a cookie that match the ones used in the cnode

```
iex --name xxxx --cookie monster
```

