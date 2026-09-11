import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../orders/data/repositories/order_repository.dart';
import '../../../../core/errors/failures.dart';

class SyncState extends Equatable {
  const SyncState({
    this.online = true,
    this.pendingCount = 0,
    this.busy = false,
    this.message,
  });

  final bool online;
  final int pendingCount;
  final bool busy;
  final String? message;

  SyncState copyWith({bool? online, int? pendingCount, bool? busy, String? message}) {
    return SyncState(
      online: online ?? this.online,
      pendingCount: pendingCount ?? this.pendingCount,
      busy: busy ?? this.busy,
      message: message,
    );
  }

  @override
  List<Object?> get props => [online, pendingCount, busy, message];
}

class SyncCubit extends Cubit<SyncState> {
  SyncCubit(this._orders) : super(const SyncState());

  final OrderRepository _orders;

  void setOnline(bool online) {
    emit(state.copyWith(online: online, pendingCount: _orders.pending().length));
    if (online) {
      drain();
    }
  }

  void refreshQueue() {
    emit(state.copyWith(pendingCount: _orders.pending().length));
  }

  Future<void> drain() async {
    if (!state.online || state.busy) {
      return;
    }
    if (_orders.pending().isEmpty) {
      emit(state.copyWith(pendingCount: 0));
      return;
    }
    emit(state.copyWith(busy: true));
    try {
      await _orders.syncPending();
      emit(state.copyWith(busy: false, pendingCount: _orders.pending().length, message: null));
    } on Failure catch (error) {
      emit(state.copyWith(busy: false, pendingCount: _orders.pending().length, message: error.message));
    }
  }
}
