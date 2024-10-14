const path = require('path')
const { lstatSync, readdirSync } = require('fs')

const basePath = path.resolve(__dirname, 'src/lambdas')
const lambdas = readdirSync(basePath).filter(name => lstatSync(path.join(basePath, name)).isDirectory())

module.exports = {
  rootDir: '.',
  coverageDirectory: '<rootDir>/coverage',
  collectCoverageFrom: ['<rootDir>/src/lambdas/*/.ts'],
  coverageThreshold: {
    global: {
      branches: 0,
      functions: 0,
      lines: 0,
      statements: 0
    }
  },
  testPathIgnorePatterns: ['<rootDir>/node_modules'],
  projects: [
    ...lambdas.map(value => ({
      displayName: value,
      transform: {
        '^.+\\.ts?$': [
          'ts-jest',
          {
            tsconfig: `<rootDir>/src/lambdas/${value}/tsconfig.json`,
            isolatedModules: true
          }
        ]
      },
      testEnvironment: 'node',
      testMatch: [`<rootDir>/src/lambdas/${value}/*.test.ts`]
    }))
  ],
  prettierPath: null
}
