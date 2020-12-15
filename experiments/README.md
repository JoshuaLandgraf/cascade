# Synergy Experiments Guide

## Intro

This guide covers running various experiments shown in our ASPLOS'21 paper. Before proceeding, make sure to set up Synergy according to [ARTIFACT.md](../ARTIFACT.md).

## Scope

Currently, we aim to provide experiments to reproduce the data depicted in line graphs presented in our paper, as they demonstrate the novel functionality Synergy provides. To make running these experiments as simple as possible, we provide programs that use Synergy's library interface to automate the process of triggering the relevant actions in each experiment.


## Building

Once Synergy has been built, building the experiments is quite simple. The Makefile builds the experiments against the version of Synergy in the local build directory, so installing Synergy isn't necessary to compile them.

    cd /home/centos/src/project_data/cascade-f1/experiments
	make

## Experiments
