class_name GameConst
extends RefCounted
## Central place for string group names, the physics layer map and shared limits.
## No autoload needed: use GameConst.GROUP_TARGETS, GameConst.LAYER_TERRAIN, etc.

# --- Groups ---------------------------------------------------------------
const GROUP_PLAYER := "player"
const GROUP_TARGETS := "targets"
const GROUP_ENEMY_MISSILES := "enemy_missiles"
const GROUP_HUD := "hud"
const GROUP_TERRAIN := "terrain"
const GROUP_SCORE := "score_system"

# --- 3D physics layers (bit values) ---------------------------------------
# Name these in Project Settings > General > Layer Names > 3D Physics:
#   1 Terrain, 2 Player, 3 Targets, 4 PlayerMissiles, 5 EnemyMissiles
const LAYER_TERRAIN := 1 << 0
const LAYER_PLAYER := 1 << 1
const LAYER_TARGETS := 1 << 2
const LAYER_PLAYER_MISSILES := 1 << 3
const LAYER_ENEMY_MISSILES := 1 << 4

# --- Layer setup (applied in code in Phase 4) -----------------------------
#   Target (Tank / SAM Area3D) : layer TARGETS,         mask none        (Target._ready)
#   Player missile             : layer PLAYER_MISSILES, mask TERRAIN | TARGETS  (Missile._ready)
#   Enemy missile              : layer ENEMY_MISSILES,  mask TERRAIN | PLAYER   (Missile._ready)
# Terrain and the jet are still on the default layer 1 (== LAYER_TERRAIN), so
# missiles still see both through the TERRAIN bit. When you later move the jet
# to layer 2, nothing here needs to change.

# --- Limits ---------------------------------------------------------------
## Hard cap on enemy (SAM) missiles alive at once across all turrets.
const MAX_ACTIVE_ENEMY_MISSILES := 4
