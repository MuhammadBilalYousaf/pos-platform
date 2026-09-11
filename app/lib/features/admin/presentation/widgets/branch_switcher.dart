import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/branch_context_cubit.dart';

class BranchSwitcher extends StatelessWidget {
  const BranchSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BranchContextCubit, BranchContextState>(
      builder: (context, state) {
        if (!state.showSwitcher) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: state.selectedBranchId,
              hint: const Text('All Branches'),
              items: [
                if (state.allowAll) const DropdownMenuItem<String?>(value: null, child: Text('All Branches')),
                for (final branch in state.branches)
                  DropdownMenuItem<String?>(value: branch.id, child: Text(branch.name)),
              ],
              onChanged: (value) => context.read<BranchContextCubit>().select(value),
            ),
          ),
        );
      },
    );
  }
}
