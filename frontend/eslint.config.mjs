import js from "@eslint/js";
import { defineConfig, globalIgnores } from "eslint/config";
import tseslint from "typescript-eslint";
import eslintPluginPrettierRecommended from "eslint-plugin-prettier/recommended";
import react from "eslint-plugin-react";
import reactHooks from "eslint-plugin-react-hooks";
import globals from "globals";

export default defineConfig([
  globalIgnores(["**/node_modules", "**/dist"]),
  js.configs.recommended,
  ...tseslint.configs.recommended.map((conf) => ({
    ...conf,
    files: ["**/*.ts", "**/*.tsx"],
  })),
  eslintPluginPrettierRecommended,
  {
    ...react.configs.flat.recommended,
    files: ["**/*.{js,jsx,ts,tsx}"],
  },
  {
    files: ["**/*.{js,jsx,ts,tsx}"],
    plugins: {
      "react-hooks": reactHooks,
    },
    rules: {
      ...reactHooks.configs.recommended.rules,
      "react/react-in-jsx-scope": "off",
    },
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.node,
      },
    },
    settings: {
      react: {
        version: "detect",
      },
    },
  },
]);
