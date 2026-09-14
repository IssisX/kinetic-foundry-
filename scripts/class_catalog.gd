extends Node

## First autoload. Forces the class_name scripts to parse before any later
## autoload reads them as identifiers.
##
## Godot 4.3's editor scan registers global classes before autoloads run.
## A headless game start on a cold checkout does not: it only knows what is
## in `.godot/global_script_class_cache.cfg`. CI has no editor session, so
## MaterialResponse would otherwise fail to parse FoundryMaterial. Preloading
## the catalog here makes the identifiers exist regardless.

const FoundryMaterial = preload("res://scripts/foundry_material.gd")
const EnergyPartition = preload("res://scripts/energy_partition.gd")
const SurfaceState = preload("res://scripts/surface_state.gd")
const ModalResonator = preload("res://scripts/modal_resonator.gd")
const Geom = preload("res://scripts/geom.gd")
const YardSubstrate = preload("res://scripts/yard_substrate.gd")
