#ifndef EADOR_RUNTIME_H
#define EADOR_RUNTIME_H

/*
 * Eador runtime candidate structures
 * Schema version: 14
 *
 * Type names are intentionally unversioned.  Keep these names stable in
 * Ghidra so existing globals, parameters, and fields continue to reference
 * the same logical types when the layouts are refined.
 *
 * Confidence convention:
 *   - no suffix: directly supported by loader/consumer usage
 *   - _candidate: likely interpretation, not yet mechanically established
 *   - unknown_: layout-preserving bytes only
 */

#define EADOR_RUNTIME_SCHEMA_VERSION 14

typedef signed int    eador_s32;
typedef unsigned int  eador_u32;
typedef unsigned char eador_u8;


/* -------------------------------------------------------------------------
 * Allegro prefix
 * -------------------------------------------------------------------------
 *
 * Only the first two fields are currently required.  This deliberately uses
 * a separate name to avoid colliding with an incompatible BITMAP definition
 * already present in Ghidra.
 */
typedef struct ALLEGRO_BITMAP_PARTIAL {
    eador_s32 w;                       /* +0x00 */
    eador_s32 h;                       /* +0x04 */
} ALLEGRO_BITMAP_PARTIAL;


/* -------------------------------------------------------------------------
 * Unified modifier namespace
 * ------------------------------------------------------------------------- */

typedef enum EadorModifierId {
    EADOR_MOD_LIFE             = 1,
    EADOR_MOD_ATTACK           = 2,
    EADOR_MOD_COUNTERATTACK    = 3,
    EADOR_MOD_DEFENCE          = 4,
    EADOR_MOD_RANGED_DEFENCE   = 5,
    EADOR_MOD_RESISTANCE       = 6,
    EADOR_MOD_SPEED            = 7,
    EADOR_MOD_RANGED_ATTACK    = 8,
    EADOR_MOD_SHOOTING_RANGE   = 9,
    EADOR_MOD_AMMUNITION       = 10,
    EADOR_MOD_STAMINA          = 11,
    EADOR_MOD_MORALE           = 12,

    EADOR_FIRST_ABILITY_ID     = 13
} EadorModifierId;

typedef struct EadorModifierPair {
    eador_s32 modifier_id;             /* +0x00 */
    eador_s32 magnitude;               /* +0x04 */
} EadorModifierPair;                  /* size 0x08 */


/* -------------------------------------------------------------------------
 * Ability metadata
 * ------------------------------------------------------------------------- */

typedef struct EadorAbilityDef {
    eador_u8  unknown_00[0x20];        /* +0x00 */

    eador_u32 text_ref_candidate;      /* +0x20 */
    eador_s32 modifier_id;             /* +0x24 */
    eador_s32 field_28;                /* +0x28 */

    eador_u8  show_magnitude;          /* +0x2C */
    eador_u8  flag_2d;                 /* +0x2D */
    eador_u8  unknown_2e[2];           /* +0x2E */

    ALLEGRO_BITMAP_PARTIAL *icon;       /* +0x30 */
} EadorAbilityDef;                    /* size 0x34 */


/* -------------------------------------------------------------------------
 * Unit-upgrade / modifier bundle metadata
 * ------------------------------------------------------------------------- */

typedef struct EadorUnitUpgradeDef {
    eador_u8  unknown_00[0x18];        /* +0x00 */
    eador_u32 text_ref_candidate;      /* +0x18 */

    /*
     * A level-up option is accepted only when every positive entry names a
     * modifier already supplied by the unit's intrinsic or instance sources.
     */
    eador_s32 required_modifier_ids_candidate[3]; /* +0x1C */

    /*
     * Modifier 0x3E in slot zero is treated specially by the level-up
     * applicator: its magnitude is a replacement unit-definition ID.
     */
    EadorModifierPair modifiers[5];    /* +0x28; terminated by modifier_id == 0 */

    eador_u8  flag_50;                 /* +0x50 */
    eador_u8  unknown_51[7];           /* +0x51 */
} EadorUnitUpgradeDef;                /* size 0x58 */


/* -------------------------------------------------------------------------
 * Static unit definition
 * ------------------------------------------------------------------------- */

#define EADOR_UNIT_LEVEL_COUNT             20
#define EADOR_UNIT_INSTANCE_LEVEL_CAP       30
#define EADOR_UNIT_UPGRADES_PER_LEVEL        6
#define EADOR_UNIT_LOOT_PER_LEVEL            5

typedef struct EadorUnitDef {
    char      name[0x18];               /* +0x000 */
    char     *description;              /* +0x018 */

    eador_s32 level;                    /* +0x01C */
    eador_s32 life;                     /* +0x020 */
    eador_s32 attack;                   /* +0x024 */
    eador_s32 counterattack;            /* +0x028 */
    eador_s32 defence;                  /* +0x02C */
    eador_s32 ranged_defence;           /* +0x030 */
    eador_s32 resistance;               /* +0x034 */
    eador_s32 speed;                    /* +0x038 */
    eador_s32 ranged_attack;            /* +0x03C */
    eador_s32 shooting_range;           /* +0x040 */
    eador_s32 ammunition;               /* +0x044 */
    eador_s32 stamina;                  /* +0x048 */
    eador_s32 morale;                   /* +0x04C */

    eador_s32 experience_value_candidate;    /* +0x050 */
    eador_s32 experience_modifier_candidate; /* +0x054 */
    eador_s32 gold_price_candidate;          /* +0x058 */
    eador_s32 gem_price_candidate;           /* +0x05C */
    eador_s32 gold_upkeep_candidate;         /* +0x060 */
    eador_s32 gem_upkeep;                    /* +0x064 */

    eador_s32 field_68;                 /* +0x068 */
    eador_s32 unit_category_candidate; /* +0x06C */
    eador_s32 field_70;                 /* +0x070 */
    eador_s32 alignment_value_candidate; /* +0x074 */
    eador_s32 field_78;                 /* +0x078 */
    eador_s32 field_7c;                 /* +0x07C */

    eador_s32 resource_ids[3];          /* +0x080 */
    eador_s32 ability_bundle_ids[5];    /* +0x08C; indices into EadorUnitUpgradeDef */

    /*
     * The executable stores these as parallel planes, not interleaved pairs.
     */
    eador_s32 upgrade_ids
        [EADOR_UNIT_LEVEL_COUNT]
        [EADOR_UNIT_UPGRADES_PER_LEVEL];       /* +0x0A0 */

    eador_s32 upgrade_weights
        [EADOR_UNIT_LEVEL_COUNT]
        [EADOR_UNIT_UPGRADES_PER_LEVEL];       /* +0x280 */

    eador_s32 loot_ids
        [EADOR_UNIT_LEVEL_COUNT]
        [EADOR_UNIT_LOOT_PER_LEVEL];           /* +0x460 */

    eador_s32 loot_weights
        [EADOR_UNIT_LEVEL_COUNT]
        [EADOR_UNIT_LOOT_PER_LEVEL];           /* +0x5F0 */

    ALLEGRO_BITMAP_PARTIAL *graphic;     /* +0x780 */
    ALLEGRO_BITMAP_PARTIAL *shadow;      /* +0x784 */
    ALLEGRO_BITMAP_PARTIAL *shadow_f;    /* +0x788 */
    ALLEGRO_BITMAP_PARTIAL *icon;        /* +0x78C */

    eador_s32 tail_field_790;            /* +0x790 */
    eador_s32 tail_field_794;            /* +0x794 */
    eador_s32 tail_field_798;            /* +0x798 */
    eador_s32 tail_field_79c;            /* +0x79C */
} EadorUnitDef;                         /* size 0x7A0 */


/* -------------------------------------------------------------------------
 * Three-slot unit attachment metadata
 * -------------------------------------------------------------------------
 *
 * Records are indexed with stride 0x88.  Only two fields are established.
 */
typedef struct EadorUnitAttachmentDefPartial {
    eador_u8  unknown_00[0x24];          /* +0x00 */
    eador_s32 gold_upkeep_delta;          /* +0x24 */
    eador_s32 gem_upkeep_delta;           /* +0x28 */
    eador_u8  unknown_2c[4];             /* +0x2C */

    /* All ten pairs are scanned for instance-side modifiers. */
    EadorModifierPair modifiers[10];     /* +0x30 */

    ALLEGRO_BITMAP_PARTIAL *icon;         /* +0x80 */
    eador_u8  unknown_84[4];             /* +0x84 */
} EadorUnitAttachmentDefPartial;        /* size 0x88 */


/* -------------------------------------------------------------------------
 * Hero state prefix referenced from a live unit
 * ------------------------------------------------------------------------- */

typedef struct EadorHeroStatePartial {
    eador_u8  unknown_00[0x0C];          /* +0x00 */
    eador_s32 experience;                /* +0x0C */
    eador_s32 level;                     /* +0x10 */
    eador_u8  unknown_14[4];             /* +0x14 */

    eador_s32 primary_class;             /* +0x18 */
    eador_s32 secondary_class_candidate; /* +0x1C */

    eador_u8  unknown_20[0x40];          /* +0x20 */
    char     *display_name;              /* +0x60 */
} EadorHeroStatePartial;                /* known prefix size 0x64 */


/* -------------------------------------------------------------------------
 * Live unit instance
 * -------------------------------------------------------------------------
 *
 * Allocation sites construct exactly 0xA4 bytes, so the complete object size
 * is now established even though many internal fields remain unresolved.
 */
typedef struct EadorUnitInstancePartial {
    eador_s32 unit_definition_id;        /* +0x00 */
    eador_s32 current_life;              /* +0x04 */

    /*
     * The details dialog divides this value by two before applying it to
     * effective morale.
     */
    eador_s32 morale_delta_times_two;    /* +0x08 */

    eador_s32 experience;                /* +0x0C */
    eador_s32 level;                     /* +0x10 */

    /*
     * Persistent tactical-formation coordinates.  Battle deployment copies
     * these into BattleUnit.grid_x/grid_y; the opposing side mirrors X as
     * 7 - formation_grid_x.  Death-time replacement units inherit both.
     */
    eador_s32 formation_grid_x;          /* +0x14 */
    eador_s32 formation_grid_y;          /* +0x18 */

    /*
     * The level calculator caps ordinary units at level 30.  The level-up
     * applicator writes one selected upgrade ID at index [level], and unit
     * transformations clear entries from the recalculated level through 29.
     *
     * Static UnitDef records provide six fresh options for only the first
     * twenty levels; later levels select from the accumulated candidate pool.
     */
    eador_s32
        level_upgrade_ids[EADOR_UNIT_INSTANCE_LEVEL_CAP]; /* +0x1C */

    eador_s32 attachment_ids[3];         /* +0x94 */
    EadorHeroStatePartial *hero_state;   /* +0xA0 */
} EadorUnitInstancePartial;             /* size 0xA4 */



/* -------------------------------------------------------------------------
 * Tactical-battle runtime candidates
 * -------------------------------------------------------------------------
 *
 * The battle engine keeps 37 fixed-size unit slots for each of two sides.
 * The complete record stride is 0x80.  Only fields directly exercised by
 * the two AI action-selection functions are named here.
 */

#define EADOR_BATTLE_SIDE_COUNT            2
#define EADOR_BATTLE_UNIT_SLOTS_PER_SIDE  37
#define EADOR_BATTLE_GRID_WIDTH            8
#define EADOR_BATTLE_GRID_HEIGHT           8
#define EADOR_BATTLE_OFFBOARD_COORDINATE  10
#define EADOR_BATTLE_ACTION_EFFECT_COUNT     8

typedef struct EadorBattleActionDefPartial EadorBattleActionDefPartial;

typedef struct EadorRuntimeModifierNodePartial {
    eador_s32 modifier_id;               /* +0x00 */
    eador_s32 magnitude;                 /* +0x04 */
    eador_s32 duration_or_stack_value_candidate; /* +0x08 */

    /* Displayed by the tactical status-panel iterator when nonzero. */
    eador_u8  visible_in_status_ui_candidate; /* +0x0C */

    /* Removed from the linked list immediately before incoming damage. */
    eador_u8  remove_on_damage_candidate;     /* +0x0D */
    eador_u8  unknown_0e[2];             /* +0x0E */

    /*
     * New nodes are inserted at the list head.  Iteration follows +0x10;
     * the old head receives a back-link to the new node at +0x14.
     */
    struct EadorRuntimeModifierNodePartial *next;     /* +0x10 */
    struct EadorRuntimeModifierNodePartial *previous; /* +0x14 */

    EadorBattleActionDefPartial *source_action_definition_candidate; /* +0x18 */
    EadorUnitUpgradeDef *source_upgrade_definition_candidate;        /* +0x1C */
} EadorRuntimeModifierNodePartial;       /* size 0x20 */

typedef enum EadorBattleDamageChannelCandidate {
    /*
     * Established from the concrete executors and central damage sink:
     *   0: melee or counterattack
     *   1: ordinary ranged attack
     *   2: ranged attack when attacker modifier 0x1C is active
     *   3: special/action damage; bypasses the normal large-hit morale check
     */
    EADOR_DAMAGE_CHANNEL_MELEE_OR_COUNTERATTACK = 0,
    EADOR_DAMAGE_CHANNEL_RANGED                 = 1,
    EADOR_DAMAGE_CHANNEL_RANGED_MODIFIER_1C     = 2,
    EADOR_DAMAGE_CHANNEL_SPECIAL_NO_MORALE      = 3
} EadorBattleDamageChannelCandidate;

typedef struct EadorBattleUnitPartial {
    eador_s32 current_life;               /* +0x00 */
    eador_s32 movement_or_action_points_candidate; /* +0x04 */

    eador_s32 current_morale;             /* +0x08 */

    /*
     * Increased in ten-point steps when morale would fall below one.
     * The downstream rout/panic interpretation is still unresolved.
     */
    eador_s32 morale_break_accumulator_candidate; /* +0x0C */

    eador_s32 current_stamina;            /* +0x10 */
    eador_s32 current_ammunition;         /* +0x14 */

    /*
     * The melee-exchange executor increments +0x18 for ordinary attacks and
     * counterattacks.  The ranged executor independently increments +0x1C.
     */
    eador_s32 melee_damage_dealt_accumulator_candidate;  /* +0x18 */
    eador_s32 ranged_damage_dealt_accumulator_candidate; /* +0x1C */

    /*
     * Indexed by EadorBattleDamageChannelCandidate before current_life is
     * reduced.  Concrete executors establish channels 0, 1 and 2; channel 3
     * is used by special/action damage and skips normal large-hit morale.
     */
    eador_s32 damage_received_by_channel_candidate[4]; /* +0x20 */

    eador_u8  unknown_30[8];              /* +0x30 */

    /*
     * Kill counters are separated by attack family in the same way as dealt
     * damage: ranged at +0x38, melee/counterattack at +0x3C.
     */
    eador_s32 ranged_kills_candidate;     /* +0x38 */
    eador_s32 melee_or_counterattack_kills_candidate; /* +0x3C */

    eador_s32 stamina_spent_candidate;    /* +0x40 */

    /* Normal battlefield coordinates are 0..7; 10 is used off-board. */
    eador_s32 grid_x;                     /* +0x44 */
    eador_s32 grid_y;                     /* +0x48 */

    eador_u8  unknown_4c[4];              /* +0x4C */

    eador_s32 side_index_candidate;       /* +0x50 */

    /*
     * Used to write a death-time replacement unit back into the owning
     * strategic army/garrison slot.
     */
    eador_s32 strategic_unit_slot_index_candidate; /* +0x54 */

    eador_u8  unknown_58[4];              /* +0x58 */

    eador_u8  turn_active_candidate;       /* +0x5C */
    eador_u8  flag_5d;                    /* +0x5D */
    eador_u8  flag_5e;                    /* +0x5E */
    eador_u8  flag_5f;                    /* +0x5F */

    /* Remains set for an on-field corpse even when current_life is zero. */
    eador_u8  present_on_field_candidate; /* +0x60 */
    eador_u8  flag_61;                    /* +0x61 */

    /*
     * Marks a battle-owned/nonpersistent unit instance.  Such units do not
     * receive commander-aura contributions; on final death their UnitInstance
     * is freed and the tactical slot is fully cleared.
     */
    eador_u8  battle_owned_unit_instance_candidate; /* +0x62 */
    eador_u8  flag_63;                    /* +0x63 */

    /*
     * Visual object whose fields are updated with unit graphic/shadow and
     * death/revival state.
     */
    void     *battle_visual_object_candidate; /* +0x64 */

    /*
     * Tactical-slot UI resources.  Side-transfer code preserves the
     * destination slot's +0x6C object while copying the unit's full 0x80-byte
     * record, which indicates that +0x6C is slot-local rather than unit-owned.
     */
    void     *status_ui_control_candidate; /* +0x68 */
    void     *status_ui_bitmap_candidate;  /* +0x6C */

    EadorUnitInstancePartial *unit_instance; /* +0x70 */

    /*
     * Preserves the original/backing unit instance while a temporary battle
     * transformation is active; death handling may restore or replace it.
     */
    EadorUnitInstancePartial
        *original_or_backup_unit_instance_candidate; /* +0x74 */

    void     *commander_or_army_context_candidate; /* +0x78 */

    EadorRuntimeModifierNodePartial
        *runtime_modifier_list_candidate; /* +0x7C */
} EadorBattleUnitPartial;                /* size 0x80 */

typedef struct EadorBattleSideRoster {
    EadorBattleUnitPartial units[EADOR_BATTLE_UNIT_SLOTS_PER_SIDE];
} EadorBattleSideRoster;                 /* size 0x1280 */


/*
 * Tactical action/spell definitions are indexed with a proven 0xE4 stride.
 * Most names describe how the AI uses the fields rather than final game-data
 * terminology.
 */
struct EadorBattleActionDefPartial {
    eador_u8  unknown_00[0x1C];          /* +0x00 */

    eador_s32 action_resource_cost_candidate; /* +0x1C */

    eador_u8  unknown_20[0x10];          /* +0x20 */

    /*
     * The action executor adjusts each clause's magnitude by:
     *   hero modifier 0x389 * this percentage / 100.
     */
    eador_s32 effect_magnitude_hero_scale_percent_candidate; /* +0x30 */

    /*
     * Positive auxiliary/duration values are adjusted by:
     *   hero modifier 0x38A * this percentage / 100.
     */
    eador_s32 effect_aux_hero_scale_percent_candidate; /* +0x34 */

    /*
     * Base resistance contribution:
     *   target effective resistance * this percentage / 100.
     * Per-clause byte coefficients at +0x54..+0x57 then use that value.
     */
    eador_s32 resistance_scale_percent_candidate; /* +0x38 */

    eador_s32 targeting_mode;            /* +0x3C */
    eador_s32 targeting_subtype;         /* +0x40 */
    eador_s32 radius_or_target_count_candidate; /* +0x44 */

    eador_u8  unknown_48[8];             /* +0x48 */

    eador_u8  invert_side_for_area_candidate; /* +0x50 */
    eador_u8  can_target_enemy;          /* +0x51 */
    eador_u8  can_target_ally;           /* +0x52 */
    eador_u8  post_action_unit_selection_candidate; /* +0x53 */

    eador_u8  unknown_54[8];             /* +0x54 */

    eador_s32 excluded_unit_categories[5]; /* +0x5C */
    eador_s32 evaluation_modifier_ids_candidate[3]; /* +0x70 */

    /*
     * Eight parallel effect clauses.  Effect type values above 1000 encode
     * a static unit-definition ID as value - 1000 in summon/creation paths.
     */
    eador_s32 effect_type_ids[EADOR_BATTLE_ACTION_EFFECT_COUNT];   /* +0x7C */
    eador_s32 effect_magnitudes[EADOR_BATTLE_ACTION_EFFECT_COUNT]; /* +0x9C */
    eador_s32 effect_aux_values[EADOR_BATTLE_ACTION_EFFECT_COUNT]; /* +0xBC */
    eador_u8  unknown_dc[4];              /* +0xDC */

    eador_s32 presentation_id_candidate;  /* +0xE0 */
};                                      /* EadorBattleActionDefPartial, size 0xE4 */

/* -------------------------------------------------------------------------
 * Strategic province and army-state candidates
 * -------------------------------------------------------------------------
 *
 * These layouts are derived from the strategic-turn orchestration function.
 * Only fields directly exercised by that function are named.  The types are
 * deliberately Partial even where the known prefix reaches a full observed
 * stride.
 */

typedef struct EadorProvinceStatePartial EadorProvinceStatePartial;
typedef struct EadorArmyStackPartial EadorArmyStackPartial;

struct EadorArmyStackPartial {
    eador_u8  unknown_00[8];             /* +0x00 */
    eador_s32 owner_ruler_id;            /* +0x08 */

    eador_s32 action_progress_candidate; /* +0x0C */
    eador_s32 level_or_type_candidate;   /* +0x10 */
    eador_u8  unknown_14[0x20];          /* +0x14 */

    eador_s32 province_id;               /* +0x34 */
    eador_s32 state;                     /* +0x38 */
    eador_s32 target_province_id;        /* +0x3C */
    eador_u8  unknown_40[0x0C];          /* +0x40 */

    eador_s32 completion_timer;          /* +0x4C */
    eador_s32 project_type_candidate;    /* +0x50 */
    eador_u8  unknown_54[0x0C];          /* +0x54 */

    char *display_name_candidate;        /* +0x60 */
    EadorProvinceStatePartial *province; /* +0x64 */

    /*
     * Several whole-stack loops include +0x68 through +0xA4 (16 pointers),
     * while troop-only calculations start at +0x6C and process 15 pointers.
     */
    EadorUnitInstancePartial *commander_unit_candidate; /* +0x68 */
    EadorUnitInstancePartial *troop_units[15];          /* +0x6C */
};                                      /* known prefix size 0xA8 */

typedef struct EadorTimedSignedValue {
    eador_s32 value;                     /* +0x00 */
    eador_s32 decay_timer;               /* +0x04 */
} EadorTimedSignedValue;                 /* size 0x08 */

typedef struct EadorProvinceSiteSlotPartial {
    eador_s32 site_definition_id;        /* +0x00 */
    eador_s32 development_requirement_candidate; /* +0x04 */
    eador_s32 field_08;                  /* +0x08 */
    eador_s32 field_0c;                  /* +0x0C */
    eador_s32 state_candidate;           /* +0x10 */
    eador_s32 field_14;                  /* +0x14 */
} EadorProvinceSiteSlotPartial;          /* size 0x18 */

struct EadorProvinceStatePartial {
    eador_u8  unknown_000[4];            /* +0x000 */
    eador_s32 province_id;               /* +0x004 */

    eador_s32 map_x;                     /* +0x008 */
    eador_s32 map_y;                     /* +0x00C */

    eador_u8  unknown_010[0x08];         /* +0x010 */
    eador_s32 owner_ruler_id;            /* +0x018 */

    eador_u8  unknown_01c[0x10];         /* +0x01C */
    eador_s32 population_candidate;      /* +0x02C */
    eador_s32 race_id;                   /* +0x030 */
    eador_s32 field_034;                 /* +0x034 */

    eador_u8  unknown_038[0x08];         /* +0x038 */
    eador_s32 field_040;                 /* +0x040 */
    eador_s32 pending_action_id;         /* +0x044 */

    eador_u8  unknown_048[0x4C];         /* +0x048 */

    /*
     * Index 0 is retained for layout.  The global-turn function updates
     * entries 1..16 at +0x9C, moving each signed value one step toward zero
     * whenever its timer expires, then resetting the timer to 20.
     */
    EadorTimedSignedValue
        ruler_relation_candidate[17];    /* +0x094 */

    eador_u8  unknown_11c[0x30];         /* +0x11C */

    EadorArmyStackPartial *garrison_stack_candidate;  /* +0x14C */
    EadorArmyStackPartial *secondary_stack_candidate; /* +0x150 */

    eador_s32 structure_ids_candidate[3]; /* +0x154 */
    eador_u8  unknown_160[0x24];          /* +0x160 */
    EadorProvinceSiteSlotPartial sites[30]; /* +0x184 */

    /*
     * Thirty pointer-sized province objects receive per-turn processing.
     * Their exact gameplay category is not yet established.
     */
    void *province_objects_candidate[30]; /* +0x454 */

    eador_u8  unknown_4cc[0x18];         /* +0x4CC */
};                                      /* observed stride 0x4E4 */

#endif /* EADOR_RUNTIME_H */
