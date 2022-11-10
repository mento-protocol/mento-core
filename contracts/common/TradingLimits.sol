pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

library TradingLimits {
    uint8 private constant L0 = 1; // 0b001 Limit0
    uint8 private constant L1 = 2; // 0b010 Limit1
    uint8 private constant LG = 4; // 0b100 LimitGlobal

    struct Data {
        uint32 timestep0;
        uint32 lastUpdated0;
        int48 limit0;
        int48 netflow0;
        uint32 timestep1;
        uint32 lastUpdated1;
        int48 limit1;
        int48 netflow1;
        int48 limitGlobal;
        int48 netflowGlobal;
        uint8 flags;
    }

    function configure(Data memory self, Data memory config) internal view  returns (Data memory) {
        require(
            config.flags & L0 == 0 || config.timestep0 > 0, 
            "timestep0 can't be zero if active"
        );
        require(
            config.flags & L1 == 0 || config.timestep1 > 0, 
            "timestep1 can't be zero if active"
        );

        if (config.flags & L0 > 0) {
            self.timestep0 = config.timestep0;
            self.lastUpdated0 = uint32(block.timestamp);
            self.limit0 = config.limit0;
            self.netflow0 = 0;
        } else {
            self.timestep0 = 0;
            self.lastUpdated0 = 0;
            self.limit0 = 0;
            self.netflow0 = 0;
        }

        if (config.flags & L1 > 0)  {
            self.timestep1 = config.timestep1;
            self.lastUpdated1 = uint32(block.timestamp);
            self.limit1 = config.limit1;
            self.netflow1 = 0;
        } else {
            self.timestep1 = 0;
            self.lastUpdated1 = 0;
            self.limit1 = 0;
            self.netflow1 = 0;
        }

        if (config.flags & LG > 0) {
            self.limitGlobal = config.limitGlobal;
        } else {
            self.limitGlobal = 0;
        }

        self.flags = config.flags;
        return self;
    }

    function update(Data memory self, int256 _deltaFlow, uint8 decimals) internal view returns (Data memory) {
        int48 deltaFlow = int48(_deltaFlow / int256((10 ** uint256(decimals))));

        if (block.timestamp > self.lastUpdated0 + self.timestep0) {
            self.netflow0 = 0;
            self.lastUpdated0 = uint32(block.timestamp);
        }
        if (block.timestamp > self.lastUpdated1 + self.timestep1) {
            self.netflow1 = 0;
            self.lastUpdated1 = uint32(block.timestamp);
        }

        self.netflow0 += (self.flags & L0) * deltaFlow;
        self.netflow1 += (self.flags & L1) * deltaFlow;
        self.netflowGlobal += (self.flags & LG) * deltaFlow;
        return self;
    }

    function isValid(Data memory self) internal pure returns (bool) {
        if ((self.flags & L0) > 0 && 
            (-1 * self.limit0 > self.netflow0 || self.netflow0 > self.limit0)) {
            revert("L0 Exceeded");
        }
        if ((self.flags & L1) > 0 && 
            (-1 * self.limit1 > self.netflow1 || self.netflow1 > self.limit1)) {
            revert("L1 Exceeded");
        }
        if ((self.flags & LG) > 0 && 
            (-1 * self.limitGlobal > self.netflowGlobal || self.netflowGlobal > self.limitGlobal)) {
            revert("LG Exceeded");
        }
        return true;
    }
}