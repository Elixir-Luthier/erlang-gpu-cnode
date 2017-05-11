BASE=$(shell elixir getpath.exs)
ERL=$(wildcard $(BASE)/lib/erl_interface-*)

OSX=""
LINUX="-lpthread -lnsl"

NVIDIA_COMMON=/home/nvidia/NVIDIA_CUDA-8.0_Samples/common/inc
NVCC=/usr/local/cuda-8.0/bin/nvcc
#-maxrregcount=16 
NVCC_OPTS=-ccbin g++ -I. -I$(NVIDIA_COMMON) -m64 -DGPU_CNODE  -gencode arch=compute_53,code=sm_53 -gencode arch=compute_60,code=sm_60 -gencode arch=compute_62,code=sm_62 -gencode arch=compute_62,code=compute_62 


all: cnode_gpu
	@echo "making everything..."

clean:
	@rm -f cnode cnode_linux cnode_gpu *.o && echo "cleaning up..."
	@echo "done."


cnode_gpu.o: cnode.cu 
	$(NVCC) $(NVCC_OPTS) -o cnode_gpu.o -c cnode.cu -L$(ERL)/lib -lerl_interface -lei -lpthread -lnsl && echo "compiling cnode for gpu..."

scalar.o: scalar.cu scalar.cuh
	$(NVCC) $(NVCC_OPTS) -o scalar.o -c scalar.cu -L$(ERL)/lib -lerl_interface -lei -lpthread -lnsl && echo "compiling cnode for gpu..."

cnode_gpu: cnode_gpu.o scalar.o
	$(NVCC) $(NVCC_OPTS) -o cnode_gpu cnode_gpu.o scalar.o -L$(ERL)/lib -lerl_interface -lei -lpthread -lnsl && echo "building cnode for gpu..."



cnode_osx: cnode.cu
	@gcc -o cnode_osx cnode.c -I$(ERL)/include -L$(ERL)/lib -lerl_interface -lei && echo "building cnode..."
	@echo "done."

cnode_linux: cnode.cu
	@gcc -o cnode_linux cnode.c -I$(ERL)/include -L$(ERL)/lib -lerl_interface -lei -lpthread -lnsl && echo "building cnode for linux..."
	@echo "done."

serve_osx: cnode_osx
	@echo "running server on port 3456"
	@echo
	@echo 'start an iex session -> iex --name "bob@mbp2016.local" --cookie monster'
	@echo
	@echo "compile the 'elix.ex' -> c elix.ex"
	./cnode_osx -p 3456 -i 127.0.0.1 -h mbp2016.local -n cnode -f cnode@mbp2016.local -c monster

serve_linux: cnode_linux
	@echo "running server on port 3456"
	@echo
	@echo 'start an iex session -> iex --name "bob@mbp2016.local" --cookie monster'
	@echo
	@echo "compile the 'elix.ex' -> c elix.ex"
	./cnode_linux -p 3456 -i 127.0.0.1 -h tegra-ubuntu -n cnode -f cnode@tegra-ubuntu.local -c monster

serve_gpu: cnode_gpu
	@echo "running server on port 3456"
	@echo
	@echo 'start an iex session -> iex --name "bob@mbp2016.local" --cookie monster'
	@echo
	@echo "compile the 'elix.ex' -> c elix.ex"
	./cnode_gpu -p 3456 -i 127.0.0.1 -h tegra-ubuntu -n cnode -f cnode@tegra-ubuntu.local -c monster
