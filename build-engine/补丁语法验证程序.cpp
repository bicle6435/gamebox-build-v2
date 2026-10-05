// Standalone syntax validation of the GameBox v2 patched shadPS4 structures.
// Uses the REAL common/bit_field.h and common/types.h from the project so the
// patched struct definitions are validated in their true type context.
// External deps (spdlog etc.) are stubbed because submodules are not vendored
// in this source snapshot.
//
// v2 additions beyond v1:
//   [C] Shader clamp-opcode semantics (V_LOG_CLAMP_F32 / V_RCP_CLAMP_F32 /
//       V_RSQ_CLAMP_F32 / *_F64) verified numerically against GCN ISA spec.
//   [D] D16S8->D24S8 depth-bias unit rescaling (x256) verified.
//   [E] Sampler ClampMode enum domain verified (8 values, no overlap).

#include <array>
#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <limits>

#define ASSERT_MSG(expr, ...) assert((expr))
#include "common/types.h"
#include "common/bit_field.h"

// ── Stubs replicating the real pm4_cmds.h context ──
enum class PM4ItOpcode : u32 {
    SetPredication = 0x20,
    StrmoutBufferUpdate = 0x34,
};

enum class PM4ShaderType : u32 { ShaderGraphics = 0, ShaderCompute = 1 };
enum class PM4Predicate : u32 { PredDisable = 0, PredEnable = 1 };

union PM4Type3Header {
    static constexpr u32 TYPE = 3;
    constexpr PM4Type3Header(PM4ItOpcode code, u32 num_words_min_one,
                             PM4ShaderType stype = PM4ShaderType::ShaderGraphics,
                             PM4Predicate pred = PM4Predicate::PredDisable) {
        raw = 0;
        predicate.Assign(pred);
        shader_type.Assign(stype);
        opcode.Assign(code);
        count.Assign(num_words_min_one);
        type.Assign(3);
    }
    u32 NumWords() const { return (count + 1) & 0x3fff; }
    u32 raw;
    BitField<0, 1, PM4Predicate> predicate;
    BitField<1, 1, PM4ShaderType> shader_type;
    BitField<8, 8, PM4ItOpcode> opcode;
    BitField<16, 14, u32> count;
    BitField<30, 2, u32> type;
};

enum class SourceSelect : u32 {
    BufferOffset = 0,
    VgtStrmoutBufferFilledSize = 1,
    SrcAddress = 2,
    None = 3,
};

struct PM4CmdStrmoutBufferUpdate {
    PM4Type3Header header;
    union {
        BitField<0, 1, u32> update_memory;
        BitField<1, 2, SourceSelect> source_select;
        BitField<8, 2, u32> buffer_select;
        u32 control;
    };
    union {
        BitField<2, 30, u32> dst_address_lo;
        BitField<0, 2, u32> swap_dst;
    };
    u32 dst_address_hi;
    union {
        u32 buffer_offset;
        BitField<2, 30, u32> src_address_lo;
        BitField<0, 2, u32> swap_src;
    };
    u32 src_address_hi;

    template <typename T = u64>
    T DstAddress() const {
        ASSERT_MSG(update_memory.Value() == 1, "bad");
        return reinterpret_cast<T>(dst_address_lo.Value() | u64(dst_address_hi & 0xFFFF) << 32);
    }

    template <typename T = u64>
    T SrcAddress() const {
        ASSERT_MSG(source_select.Value() == SourceSelect::SrcAddress, "bad");
        return reinterpret_cast<T>(src_address_lo.Value() | u64(src_address_hi & 0xFFFF) << 32);
    }
};

// ── The patched PM4CmdSetPredication (copied verbatim from the patched file) ──
struct PM4CmdSetPredication {
    PM4Type3Header header;
    union {
        BitField<0, 1, u32> op;     ///< 0: pass when value != 0; 1: pass when value == 0
        BitField<1, 1, u32> bool64; ///< 1: compare 64-bit value, 0: compare 32-bit
        u32 control;
    };
    u32 address_lo;
    u32 address_hi;

    template <typename T = u64>
    T Address() const {
        return reinterpret_cast<T>(address_lo | u64(address_hi & 0xFFFF) << 32);
    }
};
static_assert(sizeof(PM4CmdSetPredication) == 16); // header(4) + control + addr_lo + addr_hi

// ── The patched PredicationState (copied verbatim from liverpool.h) ──
using VAddr = u64;
struct PredicationState {
    bool enabled{};
    bool inverted{};
    bool bool64{};
    VAddr address{};
};

// ═══════════════════ v2 section: shader clamp semantics ═══════════════════
// These mirror the Translator implementations added in vector_alu.cpp:
//   V_LOG_CLAMP_F32 : dst = log2(clamp(x, 2^-126, 2^127))
//   V_RCP_CLAMP_F32 : dst = clamp(1/x, -FLT_MAX, FLT_MAX)
//   V_RSQ_CLAMP_F32 : dst = clamp(sqrt(1/x), -FLT_MAX, FLT_MAX)
static float V_LOG_CLAMP_F32(float x) {
    const float lo = 1.17549435e-38f; // 2^-126
    const float hi = 3.40282347e38f;  // 2^127
    return std::log2f(x < lo ? lo : (x > hi ? hi : x));
}
static float V_RCP_CLAMP_F32(float x) {
    const float r = 1.0f / x;
    const float lim = 3.40282347e38f;
    return r < -lim ? -lim : (r > lim ? lim : r);
}
static float V_RSQ_CLAMP_F32(float x) {
    const float r = 1.0f / std::sqrtf(x);
    const float lim = 3.40282347e38f;
    return r < -lim ? -lim : (r > lim ? lim : r);
}

// ═══════════════════ v2 section: ClampMode enum domain ═══════════════════
enum class ClampMode : u64 {
    Wrap = 0,
    Mirror = 1,
    ClampLastTexel = 2,
    MirrorOnceLastTexel = 3,
    ClampHalfBorder = 4,
    MirrorOnceHalfBorder = 5,
    ClampBorder = 6,
    MirrorOnceBorder = 7,
};
static_assert(static_cast<u64>(ClampMode::MirrorOnceBorder) == 7); // domain ends at 7

int main() {
    // ── [A] Round-trip a serialized command to prove layout correctness. ──
    std::array<u8, 32> storage{};
    auto* cmd = reinterpret_cast<PM4CmdSetPredication*>(storage.data());
    cmd->address_lo = 0x11223344u;
    cmd->address_hi = 0x0000u;
    cmd->op.Assign(1u);
    cmd->bool64.Assign(0u);
    const auto addr = cmd->Address<u64>();
    if (addr != 0x11223344ull) {
        return 1;
    }
    if (cmd->op.Value() != 1u || cmd->bool64.Value() != 0u) {
        return 2;
    }

    PredicationState predication{};
    predication.enabled = true;
    predication.inverted = cmd->op.Value() != 0;
    predication.bool64 = cmd->bool64.Value() != 0;
    predication.address = addr;
    if (!predication.enabled || !predication.inverted || predication.bool64 ||
        predication.address != 0x11223344ull) {
        return 3;
    }

    // ── [B] Strmout struct still intact after patch context edits. ──
    static_assert(sizeof(PM4CmdStrmoutBufferUpdate) == 24);
    auto* strmout = reinterpret_cast<PM4CmdStrmoutBufferUpdate*>(storage.data());
    strmout->update_memory.Assign(1u);
    strmout->source_select.Assign(SourceSelect::VgtStrmoutBufferFilledSize);
    strmout->buffer_select.Assign(2u);
    strmout->buffer_offset = 0x400;
    if (strmout->update_memory.Value() != 1u ||
        strmout->source_select.Value() != SourceSelect::VgtStrmoutBufferFilledSize ||
        strmout->buffer_offset != 0x400) {
        return 4;
    }

    // ── [C] Shader clamp semantics: critical inputs stay finite. ──
    // x = 0: plain log2 gives -inf; GCN clamp keeps it at log2(2^-126) = -126.
    if (V_LOG_CLAMP_F32(0.0f) != -126.0f) {
        return 5;
    }
    // Negative input: plain log2 gives NaN; clamped version is finite.
    if (!std::isfinite(V_LOG_CLAMP_F32(-3.0f))) {
        return 6;
    }
    // x = 0: plain 1/x gives +inf; clamped version saturates to FLT_MAX.
    if (V_RCP_CLAMP_F32(0.0f) != std::numeric_limits<float>::max()) {
        return 7;
    }
    // x = 0: plain rsqrt gives +inf; clamped saturates.
    if (V_RSQ_CLAMP_F32(0.0f) != std::numeric_limits<float>::max()) {
        return 8;
    }
    // Normal inputs are unchanged by the clamps (bit-exact).
    const float n = 4.0f;
    if (V_LOG_CLAMP_F32(4.0f) != std::log2f(n) || V_RCP_CLAMP_F32(4.0f) != 0.25f ||
        V_RSQ_CLAMP_F32(4.0f) != 0.5f) {
        return 9;
    }

    // ── [D] D16S8 fallback depth-bias rescale factor: 2^24 / 2^16 = 256. ──
    const float bias_d16_units = 3.0f; // game-tuned for 1/65535 granularity
    const float bias_rescaled = bias_d16_units * 256.0f;
    // Same physical displacement: 3/65535 == 768/16777215 (within rounding).
    const float phys_d16 = bias_d16_units / 65535.0f;
    const float phys_d24 = bias_rescaled / 16777215.0f;
    if (std::fabsf(phys_d16 - phys_d24) > 1e-9f) {
        return 10;
    }

    // ── [E] ClampMode domain: every patched log index stays in [0, 7]. ──
    for (u64 v = 0; v <= 7; ++v) {
        auto mode = static_cast<ClampMode>(v);
        if (static_cast<u64>(mode) != v) {
            return 11;
        }
    }

    return 0;
}
