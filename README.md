# Ethereal

Ethereal is an NFTfi protocol, where each NFT (e.g. Gem) is backed by Ether.

To mint a gem with the mint function a certain amount of Ether is required -- the amount of Ether required depends on the Gem type.

Gem types can be created and configured by the owner with the createGem and updateGem functions. Gem types can be decommisioned with the ceaseGem function.

Each gem type has an associated collection. Gem Collections can be created and configured by the owner with the createCollection and updateCollection functions.

Collections have a configured validator, which, if present degems the only address which is permissioned to mint new gems.

Collections also carry an ethereum boolean which indicates whether the Gem is backed by native ether or wrapped staked ether. This decides which asset the user will have to provide when minting their Gem.

And finally user's are able to redeem their Gem with the redeem function. This way their Gem is burned forever and they receive the backing Ether or wstETH back.