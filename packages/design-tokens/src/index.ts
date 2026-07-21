export const tokens = {
  color: {
    ink: "#0D1020",
    surface: "#171B31",
    text: "#F7F7FC",
    muted: "#AEB3C7",
    violet: "#8B7CFF",
    coral: "#FF7B86",
    mint: "#6DE6C3",
    danger: "#FF5570",
  },
  radius: { sm: 12, md: 20, lg: 28, pill: 999 },
  space: { xs: 4, sm: 8, md: 16, lg: 24, xl: 32, xxl: 48 },
  duration: { quick: 120, normal: 240, slow: 420 },
  opacity: { disabled: 0.38, muted: 0.62, glass: 0.78 },
} as const;
