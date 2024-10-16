const path=require("path");
const baseconfig= require("../../../webpack.config")

module.exports={
  ...baseconfig,
  entry:"./index.ts",
  output:{
    path: path.resolve(__dirname, "dist"),
    filename: "index.js",
    libraryTarget: "commonjs"
  }
};