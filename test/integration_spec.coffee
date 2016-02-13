plv8 = require('../plpl/src/plv8')
assert = require('assert')

copy = (x)-> JSON.parse(JSON.stringify(x))

describe 'Integration',->
  before ->
    plv8.execute("SET plv8.start_proc = 'plv8_init'")

  it 'main api test', ->
    plv8.execute(
      'SELECT fhir_drop_storage($1)',
      [JSON.stringify(resourceType: 'Patient')]
    )
    plv8.execute(
      'SELECT fhir_create_storage($1)',
      [JSON.stringify(resourceType: 'Patient')]
    )
    plv8.execute(
      'SELECT fhir_index_parameter($1)',
      [JSON.stringify(resourceType: 'Patient', name: 'name')]
    )
    plv8.execute(
      'SELECT fhir_create_resource($1)',
      [JSON.stringify(resource: {
        resourceType: 'Patient', name: [{given: 'nicola'}]
      })]
    )
    plv8.execute(
      'SELECT fhir_update_resource($1)',
      [JSON.stringify(queryString: 'given=nicola', resource: {
        resourceType: 'Patient', name: [{given: 'nicola'}]
      })])
    res = plv8.execute(
      'SELECT fhir_search($1)',
      [JSON.stringify(resourceType: 'Patient', queryString: 'name=nicola')]
    )
    bundle = JSON.parse(res[0].fhir_search)
    assert.equal(bundle.total, 1)
    assert.equal(bundle.entry[0].resource.name[0].given, 'nicola')

  it 'conformance', ->
    plv8.execute(
      'SELECT fhir_create_storage($1)',
      [JSON.stringify(resourceType: 'Order')]
    )
    conformance = plv8.execute(
      'SELECT fhir_conformance($1)',
      [JSON.stringify({somekey: 'somevalue'})]
    )
    assert.equal(
      JSON.parse(conformance[0].fhir_conformance)
        .rest[0].resource.filter(
          (resource)-> resource.type == 'Order'
        ).length,
      1
    )

  describe 'Schema storage', ->
    beforeEach ->
      plv8.execute(
        'SELECT fhir_create_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )
      plv8.execute(
        'SELECT fhir_truncate_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )

    it 'create', ->
      plv8.execute(
        'SELECT fhir_create_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )
      assert.equal(
        plv8.execute('''
          SELECT * from information_schema.tables
          WHERE table_name = 'order' AND table_schema = current_schema()
        ''').length,
        1
      )
      assert.equal(
        plv8.execute('''
          SELECT * from information_schema.tables
          WHERE table_name = 'order_history'
        ''').length,
        1
      )

    it 'drop', ->
      plv8.execute(
        'SELECT fhir_drop_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )
      assert.equal(
        plv8.execute('''
          SELECT * from information_schema.tables
          WHERE table_name = 'order' AND table_schema = current_schema()
        ''').length,
        0
      )
      assert.equal(
        plv8.execute('''
          SELECT * from information_schema.tables
          WHERE table_name = 'order_history'
        ''').length,
        0
      )

    it 'truncate', ->
      plv8.execute(
        'SELECT fhir_create_resource($1)',
        [JSON.stringify(resource: {resourceType: 'Order'})]
      )
      truncateOutcome =
        plv8.execute(
          'SELECT fhir_truncate_storage($1)',
          [JSON.stringify(resourceType: 'Order')]
        )
      issue = JSON.parse(truncateOutcome[0].fhir_truncate_storage).issue[0]
      assert.equal(issue.diagnostics, 'Resource type "Order" has been truncated')

    it 'describe', ->
      describe = plv8.execute(
        'SELECT fhir_describe_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )
      assert.equal(
        JSON.parse(describe[0].fhir_describe_storage).name,
        'order'
      )

  describe 'CRUD', ->
    before ->
      plv8.execute(
        'SELECT fhir_create_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )

    beforeEach ->
      plv8.execute(
        'SELECT fhir_truncate_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )

    it 'create', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(resource: {
              resourceType: 'Order', name: 'foo bar'
            })]
          )[0].fhir_create_resource
        )
      assert.equal(created.name, 'foo bar')

    it 'read', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(resource: {resourceType: 'Order'})]
          )[0].fhir_create_resource
        )
      readed =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_read_resource($1)',
            [JSON.stringify(id: created.id, resourceType: 'Order')]
          )[0].fhir_read_resource
        )
      assert.equal(readed.id, created.id)

    it 'vread', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(resource: {resourceType: 'Order'})]
          )[0].fhir_create_resource
        )
      created.versionId = created.meta.versionId
      vreaded =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_vread_resource($1)',
            [JSON.stringify(created)]
          )[0].fhir_vread_resource
        )
      assert.equal(created.id, vreaded.id)

    it 'update', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(resource: {resourceType: 'Order', name: 'foo'})]
          )[0].fhir_create_resource
        )
      toUpdate = copy(created)
      toUpdate.name = 'bar'

      updated =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_update_resource($1)',
            [JSON.stringify(resource: toUpdate)]
          )[0].fhir_update_resource
        )
      assert.equal(updated.name, toUpdate.name)

    it 'delete', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(allowId: true, resource: {
              id: 'toBeDeleted', resourceType: 'Order'
            })]
          )[0].fhir_create_resource
        )
      plv8.execute(
        'SELECT fhir_delete_resource($1)',
        [JSON.stringify(id: created.id, resourceType: 'Order')]
      )
      readDeleted =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_read_resource($1)',
            [JSON.stringify(id: created.id, resourceType: 'Order')]
          )[0].fhir_read_resource
        )
      assert.equal(readDeleted.resourceType, 'OperationOutcome')
      issue = readDeleted.issue[0]
      assert.equal(
        issue.details.coding[0].display,
        'The resource "toBeDeleted" has been deleted'
      )

    it 'terminate', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(allowId: true, resource: {
              id: 'toBeTerminated', resourceType: 'Order'
            })]
          )[0].fhir_create_resource
        )
      plv8.execute(
        'SELECT fhir_terminate_resource($1)',
        [JSON.stringify(resourceType: 'Order', id: created.id)]
      )
      readed =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_read_resource($1)',
            [JSON.stringify(id: created.id, resourceType: 'Order')]
          )[0].fhir_read_resource
        )
      assert.equal(
        readed.issue[0].diagnostics,
        'Resource Id "toBeTerminated" does not exist'
      )

  describe 'History', ->
    before ->
      plv8.execute(
        'SELECT fhir_create_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )

    beforeEach ->
      plv8.execute(
        'SELECT fhir_truncate_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )

    it 'resource', ->
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(resource: {
              resourceType: 'Order', name: 'foo'
            })]
          )[0].fhir_create_resource
        )
      readed =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_read_resource($1)',
            [JSON.stringify(id: created.id, resourceType: 'Order')]
          )[0].fhir_read_resource
        )
      toUpdate = copy(readed)
      toUpdate.name = 'bar'

      plv8.execute(
        'SELECT fhir_update_resource($1)',
        [JSON.stringify(resource: toUpdate)]
      )

      deleted =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_delete_resource($1)',
            [JSON.stringify(id: readed.id, resourceType: 'Order')]
          )[0].fhir_delete_resource
        )
      hx =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_resource_history($1)',
            [JSON.stringify(id: readed.id, resourceType: 'Order')]
          )[0].fhir_resource_history
        )

      assert.equal(hx.total, 3)
      assert.equal(hx.entry.length, 3)
      assert.deepEqual(hx.entry.map((entry) -> entry.request), [
        {'url': 'Order', 'method': 'POST'},
        {'url': 'Order', 'method': 'PUT'},
        {'url': 'Order', 'method': 'DELETE'}
      ])

    it 'resource type', ->
      plv8.execute(
        'SELECT fhir_create_resource($1)',
        [JSON.stringify(resource: {resourceType: 'Order', name: 'u1'})]
      )
      plv8.execute(
        'SELECT fhir_create_resource($1)',
        [JSON.stringify(resource: {resourceType: 'Order', name: 'u2'})]
      )
      created =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_create_resource($1)',
            [JSON.stringify(resource: {
              resourceType: 'Order', name: 'foo'
            })]
          )[0].fhir_create_resource
        )

      readed =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_read_resource($1)',
            [JSON.stringify(id: created.id, resourceType: 'Order')]
          )[0].fhir_read_resource
        )
      toUpdate = copy(readed)
      toUpdate.name = 'bar'

      plv8.execute(
        'SELECT fhir_update_resource($1)',
        [JSON.stringify(resource: toUpdate)]
      )

      deleted =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_delete_resource($1)',
            [JSON.stringify(id: readed.id, resourceType: 'Order')]
          )[0].fhir_delete_resource
        )
      hx =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_resource_type_history($1)',
            [JSON.stringify(resourceType: 'Order')]
          )[0].fhir_resource_type_history
        )

      assert.equal(hx.total, 5)

      assert.deepEqual(hx.entry.map((entry) -> entry.request), [
        {'url': 'Order', 'method': 'POST'},
        {'url': 'Order', 'method': 'POST'},
        {'url': 'Order', 'method': 'POST'},
        {'url': 'Order', 'method': 'PUT'},
        {'url': 'Order', 'method': 'DELETE'}
      ])

  describe 'Search', ->
    before ->
      plv8.execute(
        'SELECT fhir_drop_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )
      plv8.execute(
        'SELECT fhir_create_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )

    beforeEach ->
      plv8.execute(
        'SELECT fhir_truncate_storage($1)',
        [JSON.stringify(resourceType: 'Order')]
      )
      plv8.execute(
        'SELECT fhir_create_resource($1)',
        [JSON.stringify(resource: {
          resourceType: 'Order',
          identifier: {
            system: 'http://example.com/OrderIdentifier',
            value: 'foo'
          }
        })]
      )
      plv8.execute(
        'SELECT fhir_create_resource($1)',
        [JSON.stringify(resource: {
          resourceType: 'Order',
          identifier: {
            system: 'http://example.com/OrderIdentifier',
            value: 'bar'
          }
        })]
      )

    it 'identifier', ->
      searched =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_search($1)',
            [JSON.stringify(
              resourceType: 'Order',
              queryString: 'identifier=foo'
            )]
          )[0].fhir_search
        )
      assert.equal(searched.total, 1)

    it 'analyze', ->
      analyzed =
        JSON.parse(
          plv8.execute(
            'SELECT fhir_analyze_storage($1)',
            [JSON.stringify(resourceType: 'Order')]
          )[0].fhir_analyze_storage
        )
      assert.equal(analyzed.message, 'analyzed')

    it 'explain', ->
      explained =
        plv8.execute(
          'SELECT fhir_explain_search($1)',
          [JSON.stringify(
            resourceType: 'Order',
            queryString: 'identifier=foo'
          )]
        )[0].fhir_explain_search

      assert.equal(explained, 1)
