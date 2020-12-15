CPPFLAGS = --std=c++17
INCLUDE = -I../src/cascade
LIB = -L ../build/src/ -lcascade -lpthread -ldl

DEPENDENCIES = ../build/src/libcascade.a 
EXPERIMENTS = $(basename $(wildcard *.cc))

all: $(EXPERIMENTS)

%: %.cc $(DEPENDENCIES)
	g++ $(CPPFLAGS) $(INCLUDE) $< -o $@ $(LIB)

.PHONY: clean
clean:
	rm -f $(EXPERIMENTS) state.dat *.log
