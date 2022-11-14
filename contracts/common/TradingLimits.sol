pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;

library TradingLimits {
    uint8 private constant L0 = 1; // 0b001 Limit0
    uint8 private constant L1 = 2; // 0b010 Limit1
    uint8 private constant LG = 4; // 0b100 LimitGlobal
    int48 private constant MAX_INT48 = int48(uint48(-1) / 2);

    struct State {
        uint32 lastUpdated0;
        uint32 lastUpdated1;
        int48 netflow0;
        int48 netflow1;
        int48 netflowGlobal;
    }

    struct Config {
        uint32 timestep0;
        uint32 timestep1;
        int48 limit0;
        int48 limit1;
        int48 limitGlobal;
        uint8 flags;
    }

    function validate(Config memory self) internal view returns (bool) {
        require(
           self.flags & L1 == 0 || self.flags & L0 != 0,
           "L1 without L0 not allowed"
        );
        require(
            self.flags & L0 == 0 || self.timestep0 > 0, 
            "timestep0 can't be zero if active"
        );
        require(
            self.flags & L1 == 0 || self.timestep1 > 0, 
            "timestep1 can't be zero if active"
        );

        return true;
    }

    function verify(State memory self, Config memory config) internal pure returns (bool) {
        if ((config.flags & L0) > 0 && 
            (-1 * config.limit0 > self.netflow0 || self.netflow0 > config.limit0)) {
            revert("L0 Exceeded");
        }
        if ((config.flags & L1) > 0 && 
            (-1 * config.limit1 > self.netflow1 || self.netflow1 > config.limit1)) {
            revert("L1 Exceeded");
        }
        if ((config.flags & LG) > 0 && 
            (-1 * config.limitGlobal > self.netflowGlobal || self.netflowGlobal > config.limitGlobal)) {
            revert("LG Exceeded");
        }
        return true;
    }

    function update(
        State memory self, 
        Config memory config, 
        int256 _deltaFlow, 
        uint8 decimals
    ) internal view returns (State memory) {
        int256 _deltaFlowUnits = _deltaFlow / int256((10 ** uint256(decimals)));
        require(_deltaFlowUnits <= MAX_INT48, "dFlow too large");
        int48 deltaFlowUnits = _deltaFlowUnits == 0 ? 1 : int48(_deltaFlowUnits);

        if (config.flags & L0 > 0) {
            if (block.timestamp > self.lastUpdated0 + config.timestep0) {
                self.netflow0 = 0;
                self.lastUpdated0 = uint32(block.timestamp);
            }
            self.netflow0 += deltaFlowUnits;

            if (config.flags & L1 > 0) {
                if (block.timestamp > self.lastUpdated1 + config.timestep1) {
                    self.netflow1 = 0;
                    self.lastUpdated1 = uint32(block.timestamp);
                }
                self.netflow1 += deltaFlowUnits;
            }
        }
        if (config.flags & LG > 0) {
            self.netflowGlobal +=  deltaFlowUnits;
        }

        return self;
    }
}