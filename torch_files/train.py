from rl_tools.rl.RLArgsParser import RLArgsParser
from rl_tools.rl.Trainer import Trainer
from torch_files.Factory import (
    StrategyCallbacksFactory,
    StrategyExpertFactory,
    StrategyNetworkFactory,
    StrategyNormalizersFactory,
)
from torch_files.StrategyEvalCallback import StrategyEvalCallback
from torch_files.StrategyUDPObservation import StrategyUDPObservation


def main():
    args = RLArgsParser.parse_args()
    trainer = Trainer(
        args,
        network_factory=StrategyNetworkFactory.instance(),
        callbacks_factory=StrategyCallbacksFactory.instance(),
        normalizers_factory=StrategyNormalizersFactory.instance(),
        expert_factory=StrategyExpertFactory.instance(),
        observation_class=StrategyUDPObservation,
        eval_callback_class=StrategyEvalCallback,
    )
    if args.sweep_config:
        trainer.sweep(Trainer.load_sweep_config(args.sweep_config))
    else:
        trainer.run(overrides=getattr(args, "hyperparams", None))


if __name__ == "__main__":
    main()
