/** Host-only, pure-value actor handlers. They perform NO external I/O or payments. */
const valid = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,64}$/.test(value);
export function createSagaActors() {
  return {
    reserve_inventory_saga: async data => {
      if (!valid(data.orderId)) return {tag:'rejected',patch:{}};
      return {tag:'ok',patch:{inventory:'reserved'}};
    },
    release_inventory_saga: async data => ({
      tag:'ok',patch:{inventory:data.inventory === 'reserved' ? 'released':'unchanged'}
    }),
    authorize_payment_saga: async data => data.inventory === 'reserved'
      ? {tag:'ok',patch:{payment:'authorized'}}
      : {tag:'rejected',patch:{}},
    void_payment_saga: async data => ({
      tag:'ok',patch:{payment:data.payment === 'authorized' ? 'voided':'unchanged'}
    }),
    ship_order_saga: async data => data.rejectShipping === true
      ? {tag:'rejected',patch:{shipment:'not_created'}}
      : {tag:'ok',patch:{shipment:'created'}}
  };
}
