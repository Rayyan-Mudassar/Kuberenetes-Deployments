from app import app

def test_app_exists():
    assert app is not None

def test_health_endpoint():
    client = app.test_client()
    response = client.get('/')
    assert response.status_code in (200, 302)
