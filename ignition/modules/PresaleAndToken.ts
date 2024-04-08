import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";
import { parseEther } from "viem";

const PresaleAndTokenModule = buildModule("PresaleAndTokenModel", (m) => {
  
  const TEAM_ADDRESS = "0x36E0dD59232a92B860a297662d99827431a6F438";
  const TRES_ADDRESS = "0xe733C5Cc1f6D1B8252379F599F7318C0eb584CC6";
  const LIQ_ADDRESS = "0xcBb8a68e6CF58cb1676c75268b140E16A956b004";

  const acc = m.getAccount(0)
  
  const token = m.contract("MyToken", [acc]);

  const presale = m.contract("Presale", [token, TEAM_ADDRESS, TRES_ADDRESS, LIQ_ADDRESS]);

  m.call(token, "transferOwnership", [presale]);

  return { presale, token };
})

export default PresaleAndTokenModule;