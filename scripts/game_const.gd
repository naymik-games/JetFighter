class_name GameConst
extends RefCounted
## Central place for string group names and the physics layer map.
## No autoload needed: use GameConst.GROUP_TARGETS, GameConst.LAYER_TERRAIN, etc.

# --- Groups ---------------------------------------------------------------
const GROUP_PLAYER := "player"
const GROUP_TARGETS := "targets"
const GROUP_ENEMY_MISSILES := "enemy_missiles"
const GROUP_HUD := "hud"
const GROUP_TERRAIN := "terrain"

# --- 3D physics layers (bit values) ---------------------------------------
# Name these in Project Settings > General > Layer Names > 3D Physics:
#   1 Terrain, 2 Player, 3 Targets, 4 PlayerMissiles, 5 EnemyMissiles
# NOTE: nothing uses these yet. Everything is still on the default layer 1.
# They get applied in Phase 4 so behavior doesn't change during Phases 0-3.
const LAYER_TERRAIN := 1 << 0
const LAYER_PLAYER := 1 << 1
const LAYER_TARGETS := 1 << 2
const LAYER_PLAYER_MISSILES := 1 << 3
const LAYER_ENEMY_MISSILES := 1 << 4

# --- Planned layer / mask setup (applied in Phase 4) ----------------------
#   Terrain StaticBody : layer TERRAIN,          mask none
#   Jet                : layer PLAYER,           mask TERRAIN
#   Tank / SAM Area3D  : layer TARGETS,          mask none
#   Player missile     : layer PLAYER_MISSILES,  mask TERRAIN | TARGETS
#   Enemy missile      : layer ENEMY_MISSILES,   mask TERRAIN | PLAYER
