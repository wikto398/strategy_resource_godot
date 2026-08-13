from rl_tools.rl.RLArgsParser import RLArgsParser
from rl_tools.rl.Trainer import Trainer
from torch_files.Factory import (
    StrategyCallbacksFactory,
    StrategyNetworkFactory,
    StrategyNormalizersFactory,
)


def main():
    args = RLArgsParser.parse_args()
    trainer = Trainer(
        args,
        network_factory=StrategyNetworkFactory.instance(),
        callbacks_factory=StrategyCallbacksFactory.instance(),
        normalizers_factory=StrategyNormalizersFactory.instance(),
    )
    if args.sweep_config:
        trainer.sweep(Trainer.load_sweep_config(args.sweep_config))
    else:
        trainer.run()


if __name__ == "__main__":
    main()
