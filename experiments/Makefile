CPPFLAGS = --std=c++17
INCLUDE = -I../src/cascade
LIB = -L ../build/src/ -lcascade

DEPENDENCIES = ../build/src/libcascade.a 
EXPERIMENTS = $(basename $(wildcard *.cc))

all: $(EXPERIMENTS)

%: %.cc $(DEPENDENCIES)
	g++ $(CPPFLAGS) $(INCLUDE) $(LIB) $< -o $@

.PHONY: clean
clean:
	rm -f $(EXPERIMENTS) state.dat *.log
