module.exports = {
  env: {
    browser: false,
    es2021: true,
    mocha: true,
    node: true,
  },
  extends: [
    "standard",
    "plugin:prettier/recommended",
    "plugin:node/recommended",
  ],
  parserOptions: {
    ecmaVersion: 12,
  },
  overrides: [
    {
      files: ["hardhat.config.js"],
      globals: { task: true },
    },
    {
      files: ["hardhat-config-utils.js", "deploy/*.js"],
      globals: { network: true },
      rules: {
        "node/no-unpublished-require": "off",
      },
    },
  ],
};
