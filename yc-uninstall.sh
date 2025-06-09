#!/bin/sh

yc compute instance delete otus-vm && yc vpc subnet delete otus-subnet && yc vpc network delete otus-net