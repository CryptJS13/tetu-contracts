import {ethers} from "hardhat";
import {DeployerUtils} from "../../deploy/DeployerUtils";
import {Bookkeeper, ContractReader, ContractUtils} from "../../../typechain";
import {mkdir, writeFileSync} from "fs";
import {Erc20Utils} from "../../../test/Erc20Utils";

const exclude = new Set<string>([]);


async function main() {
  const signer = (await ethers.getSigners())[0];
  const core = await DeployerUtils.getCoreAddresses();
  const tools = await DeployerUtils.getToolsAddresses();

  const bookkeeper = await DeployerUtils.connectContract(
      signer, "Bookkeeper", core.bookkeeper) as Bookkeeper;
  const cReader = await DeployerUtils.connectContract(
      signer, "ContractReader", tools.reader) as ContractReader;
  const utils = await DeployerUtils.connectContract(
      signer, "ContractUtils", tools.utils) as ContractUtils;

  const vaults = await bookkeeper.vaults();
  console.log('vaults ', vaults.length);

  const assetsNames = {};
  const vaultsNames = {};
  for (let vault of vaults) {

    const vInfo = await cReader.vaultInfo(vault);

    console.info('vInfo.name', vInfo.name);

    // @ts-ignore
    vaultsNames[vault.toLowerCase()] = vInfo.name;

    for (let asset of vInfo.assets) {
      // @ts-ignore
      assetsNames[asset.toLowerCase()] = await Erc20Utils.tokenSymbol(asset);
    }
  }

  mkdir('./tmp', {recursive: true}, (err) => {
    if (err) throw err;
  });

  await writeFileSync('./tmp/assets_names.json', JSON.stringify(assetsNames), 'utf8');
  await writeFileSync('./tmp/vaults_names.json', JSON.stringify(vaultsNames), 'utf8');
  console.log('done');
}

main()
.then(() => process.exit(0))
.catch(error => {
  console.error(error);
  process.exit(1);
});
